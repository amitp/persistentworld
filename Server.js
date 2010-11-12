// Server for a Flash game
// amitp@cs.stanford.edu
// License: MIT

// Client/server protocol is:
// [4 bytes] x = length of JSON message
// [4 bytes] y = length of binary message
// [x bytes] JSON message
// [y bytes] binary message

var fs = require('fs');
var sys = require('util');
var net = require('net');
var http = require('http');

var crossdomainPolicy = (
    "<!DOCTYPE cross-domain-policy SYSTEM"
        + " \"http://www.adobe.com/xml/dtds/cross-domain-policy.dtd\">\n"
        + "<cross-domain-policy>\n"
        + "<site-control permitted-cross-domain-policies=\"master-only\"/>\n"
        + "<allow-access-from domain=\"*\" to-ports=\"8000,8001\"/>\n"
        + "</cross-domain-policy>\n");


// First server is HTTP, for serving the swf (don't think crossdomain needed here)
http.createServer(function (request, response) {
    sys.log(request.connection.remoteAddress + " " + request.method + " " + request.url);
    if (request.method == 'GET' && request.url == '/crossdomain.xml') {
        response.writeHead(200, {'Content-Type': 'text/xml'});
        response.write(crossdomainPolicy);
        response.end();
    } else if (request.method == 'GET' && request.url == '/world') {
        response.writeHead(200, {'Content-Type': 'application/x-shockwave-flash'});
        fs.readFile("gameclient-dbg.swf", 'binary', function (err, data) {
            if (err) throw err;
            response.write(data, 'binary');
            response.end();
        });
    } else if (request.method == 'GET' && request.url.substr(0, 5) == 'http:') {
        // People from China are probing to see if server will act as a proxy
        response.writeHead(403, "Honeypot");
        response.write("Your IP has been logged.")
        response.end();
    } else {
        response.writeHead(404, "Honeypot");
        response.write("Request from " + request.connection.remoteAddress + " has been logged.")
        response.end();
    }
}).listen(8000);


// Build the map tiles by combining data from three *.data files
function buildMap() {
    var elevation = fs.readFileSync("elevation.data");
    var moisture = fs.readFileSync("moisture.data");
    var overrides = fs.readFileSync("overrides.data");
    var map = new Buffer(2048*2048);
    for (var i = 0; i < map.length; i++) {
        var code = overrides[i] >> 4;
        if (code == 1 || code == 5 || code == 6 || code == 7 || code == 8) {
            // water
            map[i] = 0;
        } else if (code == 9 || code == 10 || code == 11 || code == 12) {
            // road/bridge
            map[i] = 1;
        } else {
            // combine moisture and elevation
            map[i] = 2 + Math.floor(elevation[i]/255.0*9) + 10*Math.floor(moisture[i]/255.0*9);
        }
    }
    return map;
}


// Server state
var clientIds = [];
var clientSpriteIds = {};  // clientid -> id
var clientPositions = {};  // clientId -> {x: y:}
var width = 2048;
var height = 2048;
var map = buildMap();  // width X height tile ids (bytes)


// Conversion from int to little-endian 32-bit binary and back
function binaryToInt32LittleEndian(buffer) {
    return buffer.charCodeAt(0) | (buffer.charCodeAt(1) << 8) | (buffer.charCodeAt(2) << 16) | (buffer.charCodeAt(3) << 24);
}

function int32ToBinaryLittleEndian(value) {
    return String.fromCharCode(value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff);
}


// Second server is plain TCP, for the game communication. It also has
// to serve the cross-domain policy file.
net.createServer(function (socket) {
    var bytesRead = 0;
    var buffer = "";
    
    var lastLogTime = new Date().getTime();
    function log(msg) {
        var thisLogTime = new Date().getTime();
        sys.log("+" + (thisLogTime - lastLogTime) + " socket" + (socket.readyState == 'open'? "" : "."+socket.readyState) + "[" + socket.remoteAddress + ":" + socket.remotePort + "] " + msg);
        lastLogTime = thisLogTime;
    }

    function socket_write(bytes, type) {
        if (!socket.write(bytes, type)) {
            // TODO: figure out why something goes wrong when write queue > 32k
            log('BUFFER IS FULL ' + socket._writeQueue.length + " " + (socket._writeQueue.length > 0? socket._writeQueue[0].length : 0));
        }
    }
    
    function sendMessage(message, binaryPayload /* optional */) {
        if (binaryPayload == null) binaryPayload = "";
        jsonMessage = JSON.stringify(message);
        if (message.type != 'pong' && message.type != 'player_positions') {
            log('sending ' + message.type + " / " + jsonMessage.length + " / " + binaryPayload.length + " " + jsonMessage);
        }
        bytes = (int32ToBinaryLittleEndian(jsonMessage.length)
                 + int32ToBinaryLittleEndian(binaryPayload.length)
                 + jsonMessage
                 + binaryPayload);
        socket_write(bytes, 'binary');
    }
    
    function handleMessage(message, binaryMessage) {
        if (message.type == 'identify') {
            clientIds.push(socket.remotePort);
            clientSpriteIds[socket.remotePort] = message.sprite_id;
        } else if (message.type == 'move') {
            // NOTE: we're temporarily using remotePort as the client id
            clientPositions[socket.remotePort] = message.to;

            // TODO: make sure that the move is valid
            var mapTiles = constructMapTiles(message.left, message.right, message.top, message.bottom);
            sendMessage({
                type: 'move_ok',
                loc: clientPositions[socket.remotePort],
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
            clientIds.forEach(function (clientId) {
                if (clientId != socket.remotePort && clientSpriteIds[clientId]) {
                    otherPositions.push({id: clientId, sprite_id: clientSpriteIds[clientId], loc: clientPositions[clientId]});
                }
            });
            sendMessage({type: 'player_positions', positions: otherPositions});
        } else if (message.type == 'map_tiles') {
            respondWithMapTiles(message.timestamp,
                                message.left, message.right,
                                message.top, message.bottom);
        } else {
            log('  -- unknown message type');
        }
    }

    function constructMapTiles(left, right, top, bottom) {
        // Clip the rectangle to the map and make sure bounds are sane
        left = Math.floor(left);
        right = Math.floor(right);
        top = Math.floor(top);
        bottom = Math.floor(bottom);
        if (left < 0) left = 0;
        if (right > width) right = width;
        if (top < 0) top = 0;
        if (bottom > height) bottom = height;
        if (right < left) right = left;
        if (bottom < top) bottom = top;
        
        var tiles = [];
        for (var x = left; x < right; x++) {
            tiles.push(map.slice(x*height + top, x*height + bottom));
        }
        return {
            left: left,
            right: right,
            top: top,
            bottom: bottom,
            binaryPayload: tiles.join("")
        };
    }
    
    socket.setEncoding("binary");
    socket.setNoDelay();
    
    socket.addListener("connect", function () {
        log("CONNECT");
    });
    socket.addListener("error", function (e) {
        log("ERROR on socket: " + e);
    });
    socket.addListener("timeout", function() {
        log("TIMEOUT");
        socket.end();
    });
    socket.addListener("drain", function() {
        log("DRAIN");
    });
    socket.addListener("data", function (data) {
        if (bytesRead == 0 && data == "<policy-file-request/>\0") {
            log("policy-file-request");
            socket.write(crossdomainPolicy, 'binary');
            socket.end();
        } else {
            // The protocol sends two lengths first. Each length is 4
            // bytes, and the two lengths tell us how many more bytes
            // we have to read.
            bytesRead += data.length;
            buffer += data;

            while (buffer.length >= 8) {
                // It's long enough that we know the length of the message
                var jsonLength = binaryToInt32LittleEndian(buffer.slice(0, 4));
                var binaryLength = binaryToInt32LittleEndian(buffer.slice(4, 8));
                // Sanity check
                if (!(8 <= jsonLength && jsonLength <= 10000)) {
                    log("ERROR: jsonLength corrupt? ", jsonLength);
                    socket.end();
                    return;
                }
                if (!(0 <= binaryLength && binaryLength <= 10000000)) {
                    log("ERROR: binaryLength corrupt? ", binaryLength);
                    socket.end();
                    return;
                }

                if (buffer.length >= 8 + jsonLength + binaryLength) {
                    // We have the message, so process it, and remove those bytes
                    jsonMessage = buffer.substr(8, jsonLength);
                    binaryMessage = buffer.substr(8 + jsonLength, binaryLength);
                    buffer = buffer.slice(8 + jsonLength + binaryLength);
                    
                    try {
                        message = JSON.parse(jsonMessage); 
                    } catch (e) {
                        log('error ' + e.message + ' while parsing: ' + JSON.stringify(jsonMessage));
                        message = null;
                    }
                    if (message != null) {
                        if (message.type != 'ping') log('handle message ' + jsonMessage);
                        handleMessage(message);
                    }
                } else {
                    // We don't have a full message, so wait
                    break;
                }
            }
        }
    });
    socket.addListener("end", function () {
        log("END");
        // TODO: need to track this socket's id, and remove from clientPositions here, or on timeout
        delete clientPositions[socket.remotePort];
        delete clientSpriteIds[socket.remotePort];
        // TODO: remove socket.remotePort from clientIds
        socket.end();
    });
}).listen(8001);

sys.log('Servers running at http://127.0.0.1:8000/ and tcp:8001');
