// Simple grid-based game server
// amitp@cs.stanford.edu
// License: MIT

require.paths.unshift('/Users/amitp/Projects/src/underscore')
var fs = require('fs');
var util = require('util');
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


// Simblocks are map blocks that the client "subscribes"
// to. Events in the subscribed areas are sent to the client: map
// tiles never change (but have to be sent once); items are
// created, used, and destroyed, but never move; creatures are
// created, changed, moved, and destroyed.
var simblockSize = 16;  // TODO: figure out best size here (24?)


function simblockLocationToId(blockX, blockY) {
    var span = map.width / simblockSize;
    if (0 <= blockX && blockX < span && 0 <= blockY && blockY < span) {
        return blockX + blockY * span;
    } else {
        util.log("ERROR: simblockLocationToId(" + blockX + "," + blockY + ") span=" + span);
        return null;
    }
}


function simblockIdToLocation(simblockId) {
    var span = map.width / simblockSize;
    return {blockX: simblockId % span, blockY: Math.floor(simblockId / span)};
}


function gridLocationToBlockId(x, y) {
    return simblockLocationToId(Math.floor(x / simblockSize), Math.floor(y / simblockSize));
}

        
function simblocksSurroundingLocation(location) {
    // TODO: we're currently generating a square but it would be
    // better for the network (spread map loads out over time) if this
    // were a circular region.
    var radius = 9;  // Approximate half-size of client viewport
    var left = Math.floor((location[0] - radius) / simblockSize);
    var right = Math.ceil((location[0] + radius) / simblockSize);
    var top = Math.floor((location[1] - radius) / simblockSize);
    var bottom = Math.ceil((location[1] + radius) / simblockSize);
    var blocks = [];
    for (var x = left; x < right; x++) {
        for (var y = top; y < bottom; y++) {
            blocks.push(simblockLocationToId(x, y));
        }
    }
    // TODO: blocks should be sorted by distance from location
    return blocks;
}


function simblockBounds(simblockId) {
    var location = simblockIdToLocation(simblockId);
    var left = location.blockX * simblockSize;
    var top = location.blockY * simblockSize;
    return {left: left, top: top, right: left+simblockSize, bottom: top+simblockSize};
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
var clientDefaultLocation = [945, 1220];

// TODO: build event manager
var eventId = 1;  // each client tracks last eventId seen
var events = {};  // map from block id to list of events (ins, del, move)

var items = {};  // map from block id to list of items in that block
var creatures = {};  // map from block id to list of creatures in that block


// TEST: create a few items
items[gridLocationToBlockId(940, 1215)] = [{sprite_id: 0xce, loc: [940, 1215], name: "tree"}];
items[gridLocationToBlockId(940, 1217)] = [{sprite_id: 0xce, loc: [940, 1217], name: "tree"}];
items[gridLocationToBlockId(911, 1222)] = [{sprite_id: 0xb1, loc: [911, 1222], name: "treasure chest"}];

// TEST: create a creature that moves around by itself
nakai = {id: "#nakai", name: 'Nakai', sprite_id: 0x72, loc: null};
moveCreature(nakai, [942, 1220]);
setInterval(function () {
    var angle = Math.floor(4*Math.random());
    var dir = [Math.round(Math.cos(0.25*angle*2*Math.PI)), Math.round(Math.sin(0.25*angle*2*Math.PI))];
    var newLoc = [nakai.loc[0] + dir[0], nakai.loc[1] + dir[1]];
    moveCreature(nakai, newLoc);
}, 200);
    
// Move a creature/player, and update the creatures mapping too. The
// original location or the target location can be null for creature birth/death.
function moveCreature(creature, to) {
    var i;
    var from = creature.loc;
    var fromBlock = from && gridLocationToBlockId(from[0], from[1]);
    var toBlock = to && gridLocationToBlockId(to[0], to[1]);

    if (fromBlock != toBlock) {
        // Remove this creature from the old block
        if (fromBlock != null) {
            i = creatures[fromBlock].indexOf(creature);
            if (i < 0) log("ERROR: creature does not exist in creatures map");
            creatures[fromBlock].splice(i, 1);
            if (!events[fromBlock]) events[fromBlock] = [];
            events[fromBlock].push({id: eventId, type: 'creature_del', obj: creature});
            eventId++;
        }
        // Add this creature to the new block
        if (toBlock != null) {
            if (!creatures[toBlock]) creatures[toBlock] = [];
            creatures[toBlock].push(creature);
            if (!events[toBlock]) events[toBlock] = [];
            events[toBlock].push({id: eventId, type: 'creature_ins', obj: creature});
            eventId++;
        }
    } else {
        events[toBlock].push({id: eventId, type: 'creature_move', obj: creature});
        eventId++;
    }

    creature.loc = to;
}


// TODO: the event queues in each block will keep getting longer;
// prune them by removing events older than the MIN of the
// eventIdPointer of all clients.


// Class to handle a single game client
function Client(connectionId, log, sendMessage) {
    this.creature = {id: connectionId, name: '??', sprite_id: null, loc: null};
    this.messages = [];
    this.subscribedTo = [];  // list of block ids
    this.eventIdPointer = eventId;  // this event and newer remain to be processed
    
    if (clients[connectionId]) log('ERROR: client id already in clients map');
    clients[connectionId] = this;

    // Tell the client which of the creature ids is itself
    sendMessage({type: 'server_identify', id: connectionId});
    
    function sendChatToAll(chatMessage) {
        for (var clientId in clients) {
            clients[clientId].messages.push(chatMessage);
        }
    }

    // The client is now subscribed to this block, so send the full contents
    function insertSubscription(blockId) {
        (items[blockId] || []).forEach(function (obj) {
            sendMessage({type: 'item_ins', obj: obj});
        });
        (creatures[blockId] || []).forEach(function (obj) {
            sendMessage({type: 'creature_ins', obj: obj});
        });
    }

    // The client no longer subscribes to this block, so remove contents
    function deleteSubscription(blockId) {
        (items[blockId] || []).forEach(function (obj) {
            sendMessage({type: 'item_del', obj: obj});
        });
        (creatures[blockId] || []).forEach(function (obj) {
            sendMessage({type: 'creature_del', obj: {id: obj.id}});
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
            if (event.type == 'creature_ins') {
                sendMessage({type: 'creature_ins', obj: event.obj});
            } else if (event.type == 'creature_del') {
                sendMessage({type: 'creature_del', obj: {id: event.obj.id}});
            } else if (event.type == 'creature_move') {
                sendMessage({type: 'creature_move', obj: {id: event.obj.id, loc: event.obj.loc}});
            }
        });
        
        // Reset the pointer to indicate that we're current
        this.eventIdPointer = eventId;
    }
    

    this.handleMessage = function(message, binaryMessage) {
        if (message.type == 'client_identify') {
            this.creature.name = message.name;
            this.creature.sprite_id = message.sprite_id;
            moveCreature(this.creature, clientDefaultLocation);
            sendChatToAll({from: this.creature.name, sprite_id: this.creature.sprite_id,
                           systemtext: " has connected.", usertext: ""});
        } else if (message.type == 'move') {
            // TODO: make sure that the move is valid
            moveCreature(this.creature, message.to);

            // NOTE: we must flush all events before subscribing to
            // new blocks, or we'll end up sending things twice. For
            // example if a creature was created in a block and then
            // we subscribe to the block, we don't want to first send
            // the creature at subscription, and then send the
            // creature again that was in the event log. Similar
            // problems exist for unsubscriptions.  TODO: investigate
            // per-block event ids.
            this.sendAllEvents();
            
            // The list of simblocks that the client should be subscribed to
            var simblocks = simblocksSurroundingLocation(this.creature.loc);
            // Compute the difference between the new list and the old list
            var inserted = setDifference(simblocks, this.subscribedTo);
            var deleted = setDifference(this.subscribedTo, simblocks);
            // Set the new list on the server side
            this.subscribedTo = simblocks;

            // The reply will tell the client where the player is now
            var reply = {type: 'move_ok', loc: this.creature.loc};
            // Set the new list on the client side
            if (inserted.length > 0) reply.simblocks_ins = inserted;
            if (deleted.length > 0) reply.simblocks_del = deleted;
            sendMessage(reply);

            // Send any additional data related to the change in subscriptions.
            inserted.forEach(insertSubscription);
            deleted.forEach(deleteSubscription);
        } else if (message.type == 'prefetch_map') {
            // For now, just send a move_ok, which will trigger the fetching of map tiles
            sendMessage({
                type: 'move_ok',
                loc: clientDefaultLocation,
                simblocks: simblocksSurroundingLocation(clientDefaultLocation)
            });
        } else if (message.type == 'map_tiles') {
            var blockRange = simblockBounds(message.simblock_id);
            var mapTiles = constructMapTiles(blockRange.left, blockRange.right, blockRange.top, blockRange.bottom);
            sendMessage({
                type: 'map_tiles',
                simblock_id: message.simblock_id,
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
            sendChatToAll({from: this.creature.name, sprite_id: this.creature.sprite_id,
                           systemtext: " says: ", usertext: message.message});
        } else {
            log('  -- unknown message type');
        }
    }

    this.handleDisconnect = function() {
        if (this.creature.sprite_id != null) {
            sendChatToAll({from: this.creature.name, sprite_id: this.creature.sprite_id,
                           systemtext: " has disconnected.", usertext: ""});
        }
        moveCreature(this.creature, null);
        delete clients[connectionId];
    }
}





server.go(Client, {'/debug': 'gameclient-dbg.swf', '/world': 'gameclient.swf'});