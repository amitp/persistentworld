// Simple grid-based game server
// amitp@cs.stanford.edu
// License: MIT

require.paths.unshift('/Users/amitp/Projects/src/underscore')
var fs = require('fs');
var util = require('util');
var assert = require('assert');
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
// "@chunk:x:y".  A grid location id looks like "@grid:x:y".
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

function gridLocationToId(x, y) {
    assert.ok(0 <= x && x < map.width && 0 <= y && y < map.height,
              "ERROR: gridLocationToId(" + x + "," + y + ") out of range");
    return '@grid:' + x + ':' + y;
}

function gridIdToLocation(gridId) {
    assert.equal(typeof gridId, 'string');
    var parse = gridId.split(':');
    assert.equal(parse.length, 3);
    assert.equal(parse[0], '@grid');
    return {x: parseInt(parse[1]), y: parseInt(parse[2])};
}

function gridIdAdjust(gridId, dx, dy) {
    var location = gridIdToLocation(gridId);
    return gridLocationToId(location.x+dx, location.y+dy);
}

function gridLocationToChunkId(x, y) {
    return chunkLocationToId(Math.floor(x / chunkSize), Math.floor(y / chunkSize));
}

function gridIdToChunkId(gridId) {
    var loc = gridIdToLocation(gridId);
    return gridLocationToChunkId(loc.x, loc.y);
}

function locIdToContainerId(locId) {
    // locId can be a gridId or an objId
    if (locId == null) {
        return null;
    } else if (locId.substr(0, 5) == '@grid') {
        return gridIdToChunkId(locId);
    } else {
        return locId;
    }
}

function chunksSurroundingLocation(gridId) {
    // TODO: we're currently generating a square but it would be
    // better for the network (spread map loads out over time) if this
    // were a circular region.  TODO: hysteresis would help too
    var radius = 9;  // Approximate half-size of client viewport
    var location = gridIdToLocation(gridId);
    var left = Math.floor((location.x - radius) / chunkSize);
    var right = Math.ceil((location.x + radius) / chunkSize);
    var top = Math.floor((location.y - radius) / chunkSize);
    var bottom = Math.ceil((location.y + radius) / chunkSize);
    var chunks = [];
    for (var x = left; x < right; x++) {
        for (var y = top; y < bottom; y++) {
            chunks.push(chunkLocationToId(x, y));
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


function mapTileAt(gridId) {
    var location = gridIdToLocation(gridId);
    if (0 <= location.x && location.x < map.width
        && 0 <= location.y && location.y < map.height) {
        return map.tiles[location.x * map.height + location.y];
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
var clientDefaultLocation = gridLocationToId(945, 1220);

// TODO: build event manager
var eventId = 1;  // each client tracks last eventId seen
var events = {};  // map from chunk id to list of events (ins, del, move)

var contents = {};  // map from location id to set of objects at that location
var objects = {};  // map from object id to object


// TEST: create a few items; HACK: use sprite_id >= 0x1000 as alternate spritesheet
createObject('#obj1', gridLocationToId(940, 1215), {sprite_id: 0x10ce, name: "tree", blocking: true});
createObject('#obj2', gridLocationToId(940, 1217), {sprite_id: 0x10ce, name: "tree", blocking: true});

// TEST: create a creature that moves around by itself
nakai = createObject('#nakai', gridLocationToId(942, 1220), {name: 'Nakai', sprite_id: 0x72});
setInterval(function () {
    var angle = Math.floor(4*Math.random());
    var dx = Math.round(Math.cos(0.25*angle*2*Math.PI));
    var dy = Math.round(Math.sin(0.25*angle*2*Math.PI));
    var oldLoc = nakai.loc;
    var newLoc = gridIdAdjust(nakai.loc, dx, dy);
    if (!obstacleAtLocation(newLoc)) {
        moveObject(nakai, newLoc);
        var obj = createObject(null, oldLoc, {sprite_id: 0x10b1, name: "treasure chest"});
        setTimeout(function () {  destroyObject(obj); }, 5000);
    }
}, 2000);


// Check if any item or creature is at this location, and return it or null if none
function objectAtLocation(loc) {
    function test(obj) { return obj.loc == loc; }
    var chunkId = gridIdToChunkId(loc);
    return _.detect(contents[chunkId] || [], test) || null;
}

// Check if the map or any object would block movement to this location
function obstacleAtLocation(loc) {
    function test(obj) { return obj.loc == loc && obj.blocking; }
    var chunkId = gridIdToChunkId(loc);
    var firstObstacle = _.detect(contents[chunkId] || [], test);
    if (firstObstacle) { return firstObstacle; }
    var waterAtDestination = (mapTileAt(loc) == 0);
    if (waterAtDestination) { return {name: "water"}; }
    return null;
}


// Create an object and insert it into the appropriate maps. If id is
// null, create a fresh id.
var _obj_id_counter = 1;
function createObject(id, locId, params) {
    assert.equal(params.id, null, "Fresh object params should have no id");
    assert.equal(params.loc, null, "Fresh object params should have no loc");
    if (id == null) {
        id = '#obj:' + _obj_id_counter;
        _obj_id_counter += 1;
    }
    assert.equal(objects[id], null, "createObject() with id "+id+" already exists.");
    params.id = id;
    params.loc = null;
    objects[id] = params;
    moveObject(params, locId);
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
// original location or the target location can be null for creature birth/death.
function moveObject(object, to) {
    var i;
    // TODO: from and to can be other objects, not only grid locations
    var from = object.loc;
    var fromChunk = locIdToContainerId(from);
    var toChunk = locIdToContainerId(to);

    object.loc = to;
    if (fromChunk != toChunk) {
        // Remove this object from the old block
        if (fromChunk != null) {
            i = contents[fromChunk].indexOf(object);
            assert.ok(i >= 0, "ERROR: object does not exist in contents map");
            contents[fromChunk].splice(i, 1);
            if (!events[fromChunk]) events[fromChunk] = [];
            events[fromChunk].push({id: eventId, type: 'del', obj: object});
            eventId++;
        }
        // Add this object to the new block
        if (toChunk != null) {
            if (!contents[toChunk]) contents[toChunk] = [];
            contents[toChunk].push(object);
            if (!events[toChunk]) events[toChunk] = [];
            events[toChunk].push({id: eventId, type: 'ins', obj: object});
            eventId++;
        }
    } else {
        if (!events[toChunk]) events[toChunk] = [];
        events[toChunk].push({id: eventId, type: 'move',
                              obj: {id: object.id, loc: object.loc}});
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
            var obstacle = obstacleAtLocation(message.to);
            if (obstacle) {
                // We're not going to allow this move
                this.messages.push({from: this.object.name, sprite_id: this.object.sprite_id,
                                    systemtext: " blocked by ", usertext: obstacle.name});
            } else if (this.object.loc != message.to) {
                moveObject(this.object, message.to);
            }

            // NOTE: we must flush all events before subscribing to
            // new blocks, or we'll end up sending things twice. For
            // example if a creature was created in a block and then
            // we subscribe to the block, we don't want to first send
            // the creature at subscription, and then send the
            // creature again that was in the event log. Similar
            // problems exist for unsubscriptions.  TODO: investigate
            // per-block event ids.
            this.sendAllEvents();
            
            // The list of chunks that the client should be subscribed to
            var chunks = chunksSurroundingLocation(this.object.loc);
            // Compute the difference between the new list and the old list
            var inserted = setDifference(chunks, this.subscribedTo);
            var deleted = setDifference(this.subscribedTo, chunks);
            // Set the new list on the server side
            this.subscribedTo = chunks;

            // The reply will tell the client where the player is now
            var reply = {type: 'move_ok', loc: this.object.loc};
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
                loc: clientDefaultLocation,
                chunks: chunksSurroundingLocation(clientDefaultLocation)
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





server.go(Client, {'/debug': 'gameclient-dbg.swf', '/world': 'gameclient.swf'});