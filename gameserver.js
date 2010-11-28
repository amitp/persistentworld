// Simple grid-based game server
// amitp@cs.stanford.edu
// License: MIT

var fs = require('fs');

require.paths.unshift('.');
server = require('Server');

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
        return -1;
    }
}


function simblockIdToLocation(simblockId) {
    var span = map.width / simblockSize;
    return {blockX: simblockId % span, blockY: Math.floor(simblockId / span)};
}


function simblocksSurroundingLocation(location) {
    var radius = 9;  // Approximate half-size of client viewport
    var left = Math.floor((location[0] - radius) / simblockSize);
    var right = Math.ceil((location[0] + radius) / simblockSize);
    var top = Math.floor((location[1] - radius) / simblockSize);
    var bottom = Math.ceil((location[1] + radius) / simblockSize);
    var blocks = [];
    for (var x = left; x <= right; x++) {
        for (var y = top; y <= bottom; y++) {
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


// Class to handle a single game client
function Client(connectionId, log, sendMessage) {
    this.id = connectionId;
    this.messages = [];
    this.name = '??'
    this.sprite_id = null;
    this.loc = clientDefaultLocation;
    
    if (clients[this.id]) log('ERROR: client id already in clients map');
    clients[this.id] = this;

    function sendChatToAll(chatMessage) {
        for (var clientId in clients) {
            clients[clientId].messages.push(chatMessage);
        }
    }
    
    this.handleMessage = function(message, binaryMessage) {
        if (message.type == 'identify') {
            this.name = message.name;
            this.sprite_id = message.sprite_id;
            sendChatToAll({from: this.name, sprite_id: this.sprite_id,
                           systemtext: " has connected.", usertext: ""});
        } else if (message.type == 'move') {
            // NOTE: we're temporarily using remotePort as the client id
            this.loc = message.to;

            // Include a list of simblocks that the client is now subscribed to
            // TODO: only send this if the set has changed from last time
            // TODO: also send add/del messages for items and characters in changed blocks
            var simblocks = simblocksSurroundingLocation(message.to);
            
            // TODO: make sure that the move is valid
            sendMessage({
                type: 'move_ok',
                loc: this.loc,
                simblocks: simblocks,
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
                                         sprite_id: clients[clientId].sprite_id,
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
            sendChatToAll({from: this.name, sprite_id: this.sprite_id,
                           systemtext: " says: ", usertext: message.message});
        } else {
            log('  -- unknown message type');
        }
    }

    this.handleDisconnect = function() {
        if (this.sprite_id != null) {
            sendChatToAll({from: this.name, sprite_id: this.sprite_id,
                           systemtext: " has disconnected.", usertext: ""});
        }
        delete clients[this.id];
    }
}





server.go(Client, {'/debug': 'gameclient-dbg.swf', '/world': 'gameclient.swf'});