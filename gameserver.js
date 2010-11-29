// Simple grid-based game server
// amitp@cs.stanford.edu
// License: MIT

var fs = require('fs');
var util = require('util');
var server = require('./Server');


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
        return -1;
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

var items = {};  // map from block id to list of items in that block


// For testing: create a few items
items[gridLocationToBlockId(940, 1215)] = [{sprite_id: 0xce, loc: [940, 1215], name: "tree"}];
items[gridLocationToBlockId(940, 1217)] = [{sprite_id: 0xce, loc: [940, 1217], name: "tree"}];
items[gridLocationToBlockId(911, 1222)] = [{sprite_id: 0xb1, loc: [911, 1222], name: "treasure chest"}];


// Class to handle a single game client
function Client(connectionId, log, sendMessage) {
    this.id = connectionId;
    this.messages = [];
    this.name = '??'
    this.spriteId = null;
    this.loc = clientDefaultLocation;
    this.subscribedTo = [];  // list of block ids
    
    
    if (clients[this.id]) log('ERROR: client id already in clients map');
    clients[this.id] = this;

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
    }

    // The client no longer subscribes to this block, so remove contents
    function deleteSubscription(blockId) {
        (items[blockId] || []).forEach(function (obj) {
            sendMessage({type: 'item_del', obj: obj});
        });
    }

    
    this.handleMessage = function(message, binaryMessage) {
        if (message.type == 'identify') {
            this.name = message.name;
            this.spriteId = message.sprite_id;
            sendChatToAll({from: this.name, sprite_id: this.spriteId,
                           systemtext: " has connected.", usertext: ""});
        } else if (message.type == 'move') {
            // TODO: make sure that the move is valid
            this.loc = message.to;

            // The list of simblocks that the client should be subscribed to
            var simblocks = simblocksSurroundingLocation(this.loc);
            // Compute the difference between the new list and the old list
            var inserted = setDifference(simblocks, this.subscribedTo);
            var deleted = setDifference(this.subscribedTo, simblocks);
            // Set the new list on the server side
            this.subscribedTo = simblocks;

            // The reply will tell the client where the player is now
            var reply = {type: 'move_ok', loc: this.loc};
            // Set the new list on the client side
            if (inserted.length > 0) reply.simblocks_ins = inserted;
            if (deleted.length > 0) reply.simblocks_del = deleted;
            sendMessage(reply);

            // Send any additional data related to the change in subscriptions
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
            sendMessage({type: 'pong', timestamp: message.timestamp});

            // For now, send back all other client positions. In the
            // future, set up a map structure that has a last-changed
            // time per tile, and only send back things that have
            // moved.
            var otherPositions = [];
            for (clientId in clients) {
                if (clientId != this.id && clients[clientId].name != null) {
                    otherPositions.push({id: clientId,
                                         name: clients[clientId].name,
                                         sprite_id: clients[clientId].spriteId,
                                         loc: clients[clientId].loc
                                        });
                }
            }
            if (otherPositions.length > 0) {
                sendMessage({type: 'player_positions', positions: otherPositions});
            }
            if (this.messages.length > 0) {
                sendMessage({type: 'messages', messages: this.messages});
                this.messages = [];
            }
        } else if (message.type == 'message') {
            // TODO: handle special commands
            // TODO: handle empty messages (after spaces stripped)
            sendChatToAll({from: this.name, sprite_id: this.spriteId,
                           systemtext: " says: ", usertext: message.message});
        } else {
            log('  -- unknown message type');
        }
    }

    this.handleDisconnect = function() {
        if (this.spriteId != null) {
            sendChatToAll({from: this.name, sprite_id: this.spriteId,
                           systemtext: " has disconnected.", usertext: ""});
        }
        delete clients[this.id];
    }
}





server.go(Client, {'/debug': 'gameclient-dbg.swf', '/world': 'gameclient.swf'});