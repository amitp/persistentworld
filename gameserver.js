// Simple grid-based game server
// amitp@cs.stanford.edu
// License: MIT

"use strict";

require.paths.unshift('/Users/amitp/Projects/src/underscore')
var fs = require('fs');
var util = require('util');
var assert = require('assert');
var net = require('net');
var repl = require('repl');
var server = require('./Server');
var _ = require('underscore');


// Utility functions:

function setDifference(set1, set2) {
    return set1.filter(function (x) { return set2.indexOf(x) < 0; });
}


// Map handling:

// Build the map tiles by combining data from three *.data files
var map = {width: 2048, height: 2048};
function buildMap() {
    var elevation = fs.readFileSync("elevation.data");
    var moisture = fs.readFileSync("moisture.data");
    var overrides = fs.readFileSync("overrides.data");
    map.tiles = new Buffer(map.width*map.height);
    for (var i = 0; i < map.tiles.length; i++) {
        var code = overrides[i] >> 4;
        if (code == 1 || code == 5 || code == 6 || code == 7 || code == 8) {
            // water
            map.tiles[i] = 0;
        } else if (code == 9 || code == 10 || code == 11 || code == 12) {
            // road/bridge
            map.tiles[i] = 1;
        } else {
            // combine moisture and elevation
            map.tiles[i] = 2 + Math.floor(elevation[i]/255.0*9) + 10*Math.floor(moisture[i]/255.0*9);
        }
    }
}
buildMap();


// Chunks are blocks of the map. The server simulates objects one
// chunk at a time. The client subscribes to chunks. Events in the
// subscribed areas are sent to the client.  A chunk id looks like
// "@chunk:x:y".  Within that chunk the grid location is stored in x: y:
var chunkSize = 16;

function chunkLocationToId(chunkX, chunkY) {
    var span = map.width / chunkSize;
    assert.ok(0 <= chunkX && chunkX < span && 0 <= chunkY && chunkY < span,
              "ERROR: chunkLocationToId(" + chunkX + "," + chunkY + ") out of range");
    return '@chunk:' + chunkX + ':' + chunkY;
}

function chunkIdToLocation(chunkId) {
    var span = map.width / chunkSize;
    var parse = chunkId.split(':');
    assert.equal(parse.length, 3);
    assert.equal(parse[0], '@chunk');
    return {chunkX: parseInt(parse[1]), chunkY: parseInt(parse[2])};
}

function coordToChunkId(x, y) {
    return chunkLocationToId(Math.floor(x / chunkSize), Math.floor(y / chunkSize));
}

function chunksSurroundingCoord(x, y) {
    // TODO: we're currently generating a square but it would be
    // better for the network (spread map loads out over time) if this
    // were a circular region.  TODO: hysteresis would help too
    var radius = 9;  // Approximate half-size of client viewport
    var left = Math.floor((x - radius) / chunkSize);
    var right = Math.ceil((x + radius) / chunkSize);
    var top = Math.floor((y - radius) / chunkSize);
    var bottom = Math.ceil((y + radius) / chunkSize);
    var chunks = [];
    for (var cx = left; cx < right; cx++) {
        for (var cy = top; cy < bottom; cy++) {
            chunks.push(chunkLocationToId(cx, cy));
        }
    }
    // TODO: chunks should be sorted by distance from location
    return chunks;
}


function chunkBounds(chunkId) {
    var location = chunkIdToLocation(chunkId);
    var left = location.chunkX * chunkSize;
    var top = location.chunkY * chunkSize;
    return {left: left, top: top, right: left+chunkSize, bottom: top+chunkSize};
}


function mapTileAt(x, y) {
    if (0 <= x && x < map.width && 0 <= y && y < map.height) {
        return map.tiles[x * map.height + y];
    } else {
        return null;
    }
}
    
function constructMapTiles(left, right, top, bottom) {
    // Clip the rectangle to the map and make sure bounds are sane
    if (left < 0) left = 0;
    if (right > map.width) right = map.width;
    if (top < 0) top = 0;
    if (bottom > map.height) bottom = map.height;
    if (right < left) right = left;
    if (bottom < top) bottom = top;
    
    var tiles = [];
    for (var x = left; x < right; x++) {
        tiles.push(map.tiles.slice(x*map.height + top, x*map.height + bottom));
    }
    return {
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        binaryPayload: tiles.join("")
    };
}


//////////////////////////////////////////////////////////////////////

// Server state
var clients = {};  // map from the client.id to the Client object
var clientDefaultLocation = {x: 945, y: 1220};

// TODO: build event manager
var eventId = 1;  // each client tracks last eventId seen
var events = {};  // map from chunk id to list of events (ins, del, move)

var contents = {};  // map from location id to set of objects at that location
var objects = {};  // map from object id to object


// TEST: create a few items; HACK: use sprite_id >= 0x1000 as alternate spritesheet
createObject('#obj1', [940, 1215], {sprite_id: 0x10ce, name: "tree", blocking: true});
createObject('#obj2', [940, 1217], {sprite_id: 0x10ce, name: "tree", blocking: true});

// TEST: create a creature that moves around by itself
nakai = createObject('#nakai', [942, 1220], {name: 'Nakai', sprite_id: 0x72});
setInterval(function () {
    var angle = Math.floor(4*Math.random());
    var dx = Math.round(Math.cos(0.25*angle*2*Math.PI));
    var dy = Math.round(Math.sin(0.25*angle*2*Math.PI));
    var oldLoc = {x: nakai.x, y: nakai.y};
    var newLoc = {x: nakai.x + dx, y: nakai.y + dy};
    if (!obstacleAtCoord(newLoc.x, newLoc.y)) {
        moveObject(nakai, null, newLoc.x, newLoc.y);
        if (Math.random() < 0.01) {
            var obj = createObject(null, '#nakai', {sprite_id: 0x10b1, name: "treasure chest"});
            moveObject(obj, null, oldLoc.x, oldLoc.y);
            sendChatToAll({from: nakai.name, sprite_id: nakai.sprite_id,
                           systemtext: " dropped ", usertext: obj.name});
            setTimeout(function () { destroyObject(obj); }, 10000);
        }
    }
}, 2000);


// Check if the map or any object would block movement to this location
function obstacleAtCoord(x, y) {
    var chunkId = coordToChunkId(x, y);
    function test(obj) {
        return obj.loc == chunkId && obj.x == x && obj.y == y && obj.blocking;
    }
    var firstObstacle = _.detect(contents[chunkId] || [], test);
    if (firstObstacle) { return firstObstacle; }
    var waterAtDestination = (mapTileAt(x, y) == 0);
    if (waterAtDestination) { return {name: "water"}; }
    return null;
}


// Create an object and insert it into the appropriate maps. If id is
// null, create a fresh id.  If location is a 2-element array, treat it as
// [grid x, grid y] and turn it into a loc + subloc.
var _obj_id_counter = 1;
function createObject(id, location, params) {
    var x = null, y = null;
    assert.equal(params.id, null, "Fresh object params should have no id");
    assert.equal(params.loc, null, "Fresh object params should have no loc");
    if (id == null) {
        id = '#obj:' + _obj_id_counter;
        _obj_id_counter += 1;
    }
    if (typeof location != 'string') {
        x = location[0];
        y = location[1];
        location = coordToChunkId(x, y);
    }
    assert.equal(objects[id], null, "createObject() with id "+id+" already exists.");
    params.id = id;
    params.loc = null;
    objects[id] = params;
    moveObject(params, location, x, y);
    return params;
}
                     
// Destroy an object and update the appropriate maps
function destroyObject(obj) {
    assert.ok(obj.id, "destroyObject() with no id " + JSON.stringify(obj));
    assert.ok(objects[obj.id], "destroyObject() with id "+obj.id+" does not exist.");
    moveObject(obj, null);
    delete objects[obj.id];
    // obj.id = null;
}
                     
// Move a creature/player, and update the creatures mapping too. The
// original location or the target location can be null for creature
// birth/death.  If to==null but x,y != null then to will be set to
// the chunk containing coord x,y.
function moveObject(object, to, x, y) {
    var i;
    var from = object.loc;

    if (to == null && x != null && y != null) {
        to = coordToChunkId(x, y);
    }

    object.loc = to;
    if (x != null || y != null) {
        object.x = x;
        object.y = y;
    } else {
        delete object.x;
        delete object.y;
    }
    
    if (from != to) {
        // Remove this object from the old block
        if (from != null) {
            i = contents[from].indexOf(object);
            assert.ok(i >= 0, "ERROR: object does not exist in contents map");
            contents[from].splice(i, 1);
            if (!events[from]) events[from] = [];
            events[from].push({id: eventId, type: 'del', obj: {id: object.id}});
            eventId++;
        }
        // Add this object to the new block
        if (to != null) {
            if (!contents[to]) contents[to] = [];
            contents[to].push(object);
            if (!events[to]) events[to] = [];
            events[to].push({id: eventId, type: 'ins', obj: object});
            eventId++;
        }
    } else {
        if (!events[to]) events[to] = [];
        objStub = {id: object.id, loc: object.loc};
        if (x != null || y != null) {
            objStub.x = x;
            objStub.y = y;
        }
        events[to].push({id: eventId, type: 'move', obj: objStub});
        eventId++;
    }
}


// TODO: the event queues in each block will keep getting longer;
// prune them by removing events older than the MIN of the
// eventIdPointer of all clients.


function sendChatToAll(chatMessage) {
    for (var clientId in clients) {
        clients[clientId].messages.push(chatMessage);
    }
}


// Class to handle a single game client
function Client(connectionId, log, sendMessage) {
    this.object = {id: connectionId, name: '', sprite_id: null, loc: null};
    this.messages = [];
    this.subscribedTo = [];  // list of block ids
    this.eventIdPointer = eventId;  // this event and newer remain to be processed
    
    if (clients[connectionId]) log('ERROR: client id already in clients map');
    clients[connectionId] = this;

    // Tell the client which of the object ids is itself
    sendMessage({type: 'server_identify', id: connectionId});
    
    // The client is now subscribed to this block, so send the full contents
    function insertSubscription(blockId) {
        (contents[blockId] || []).forEach(function (obj) {
            // TODO: be consistent with event generator, with what fields sent to client
            sendMessage({type: 'obj_ins', obj: obj});
        });
    }

    // The client no longer subscribes to this block, so remove contents
    function deleteSubscription(blockId) {
        (contents[blockId] || []).forEach(function (obj) {
            sendMessage({type: 'obj_del', obj: {id: obj.id}});
        });
    }

    // Send all pending events from sim blocks
    this.sendAllEvents = function() {
        // Send back events in the subscribed blocks:
        var eventsNewerThan = this.eventIdPointer;
        var eventsToSend = [];
        this.subscribedTo.forEach(function (blockId) {
            (events[blockId] || []).forEach(function (event) {
                if (event.id >= eventsNewerThan) {
                    eventsToSend.push(event);
                }
            });
        });
        
        // Sort the events by id. That way a del followed by an
        // ins in another block will be handled properly by the
        // client.
        eventsToSend.sort(function (a, b) { return a.id - b.id; });
        
        // Send an event per message:
        eventsToSend.forEach(function (event) {
            if (event.type == 'ins') {
                sendMessage({type: 'obj_ins', obj: event.obj});
            } else if (event.type == 'del') {
                sendMessage({type: 'obj_del', obj: event.obj});
            } else if (event.type == 'move') {
                sendMessage({type: 'obj_move', obj: event.obj});
            }
        });
        // TODO: combine del+ins into a move
        // TODO: flatten del and move to not have an 'obj' field at all
        
        // Reset the pointer to indicate that we're current
        this.eventIdPointer = eventId;
    }
    

    this.handleMessage = function(message, binaryMessage) {
        if (message.type == 'client_identify') {
            this.object.name = message.name;
            this.object.sprite_id = message.sprite_id;
            // Tell this player about everyone else
            var myCreature = this.object;
            var otherPlayers = _.pluck(_.select(_.pluck(_.values(clients), 'object'),
                                                function (c) {
                                                    return c != myCreature && c.name != '';
                                                }),
                                       'name');
            if (otherPlayers.length > 0) {
                this.messages.push({systemtext: "Connected: ",
                                    usertext: otherPlayers.join(", ")});
            }
            // Tell everyone else that this player connected
            sendChatToAll({from: this.object.name, sprite_id: this.object.sprite_id,
                           systemtext: " has connected.", usertext: ""});
        } else if (message.type == 'move') {
            var obstacle = obstacleAtCoord(message.x, message.y);
            if (obstacle) {
                // We're not going to allow this move
                this.messages.push({from: this.object.name, sprite_id: this.object.sprite_id,
                                    systemtext: " blocked by ", usertext: obstacle.name});
            } else {
                moveObject(this.object, null, message.x, message.y);
            }

            // NOTE: we must flush all events before subscribing to
            // new chunks, or we'll end up sending things twice. For
            // example if a creature was created in a chunk and then
            // we subscribe to the chunk, we don't want to first send
            // the creature at subscription, and then send the
            // creature again that was in the event log. Similar
            // problems exist for unsubscriptions.  TODO: investigate
            // per-chunk event ids.
            this.sendAllEvents();
            
            // The list of chunks that the client should be subscribed to
            var chunks = chunksSurroundingCoord(this.object.x, this.object.y);
            // Compute the difference between the new list and the old list
            var inserted = setDifference(chunks, this.subscribedTo);
            var deleted = setDifference(this.subscribedTo, chunks);
            // Set the new list on the server side
            this.subscribedTo = chunks;

            // The reply will tell the client where the player is now
            var reply = {type: 'move_ok', loc: this.object.loc,
                         x: this.object.x, y: this.object.y};
            // Set the new list on the client side
            if (inserted.length > 0) reply.chunks_ins = inserted;
            if (deleted.length > 0) reply.chunks_del = deleted;
            sendMessage(reply);

            // Send any additional data related to the change in subscriptions.
            inserted.forEach(insertSubscription);
            deleted.forEach(deleteSubscription);
        } else if (message.type == 'prefetch_map') {
            // For now, just send a move_ok, which will trigger the fetching of map tiles
            // TODO: this should share code with 'move' handler, sending ins/del events
            sendMessage({
                type: 'move_ok',
                loc: coordToChunkId(clientDefaultLocation.x, clientDefaultLocation.y),
                x: clientDefaultLocation.x,
                y: clientDefaultLocation.y,
                chunks: chunksSurroundingLocation(clientDefaultLocation.x, clientDefaultLocation.y)
            });
        } else if (message.type == 'map_tiles') {
            var blockRange = chunkBounds(message.chunk_id);
            var mapTiles = constructMapTiles(blockRange.left, blockRange.right, blockRange.top, blockRange.bottom);
            sendMessage({
                type: 'map_tiles',
                chunk_id: message.chunk_id,
                left: mapTiles.left,
                right: mapTiles.right,
                top: mapTiles.top,
                bottom: mapTiles.bottom,
            }, mapTiles.binaryPayload);
        } else if (message.type == 'ping') {
            // Send back all events that have occurred since the last ping
            sendMessage({type: 'pong', timestamp: message.timestamp});

            // Send back message events:
            if (this.messages.length > 0) {
                sendMessage({type: 'messages', messages: this.messages});
                this.messages = [];
            }

            this.sendAllEvents();
        } else if (message.type == 'message') {
            // TODO: handle special commands
            // TODO: handle empty messages (after spaces stripped)
            sendChatToAll({from: this.object.name, sprite_id: this.object.sprite_id,
                           systemtext: " says: ", usertext: message.message});
        } else {
            log('  -- unknown message type');
        }
    }

    this.handleDisconnect = function() {
        if (this.object.sprite_id != null) {
            sendChatToAll({from: this.object.name, sprite_id: this.object.sprite_id,
                           systemtext: " has disconnected.", usertext: ""});
            moveObject(this.object, null);
        }
        delete clients[connectionId];
    }
}


net.createServer(function (socket) {
    var context = repl.start("gameserver> ", socket).context;
    context.clients = clients;
    context.events = events;
    context.contents = contents;
    context.objects = objects;
}).listen(5001);

server.go(Client, {'/debug': 'gameclient-dbg.swf', '/world': 'gameclient.swf'});