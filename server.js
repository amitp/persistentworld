// Server for a Flash game
// amitp@cs.stanford.edu
// License: MIT

// Client/server protocol is:
// [4 bytes] x = length of JSON message
// [4 bytes] y = length of binary message
// [x bytes] JSON message
// [y bytes] binary message


var fs = require('fs');
var sys = require('sys');
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
    sys.log(request.method + " " + request.url);
    if (request.method == 'GET' && request.url == "/crossdomain.xml") {
        response.sendHeader(200, {'Content-Type': 'text/xml'});
        response.write(crossdomainPolicy);
        response.close();
    } else if (request.method == 'GET' && request.url == "/") {
        response.sendHeader(200, {'Content-Type': 'application/x-shockwave-flash'});
        fs.readFile("client-dbg.swf", "binary", function (err, data) {
            if (err) throw err;
            response.write(data, "binary");
            response.close();
        });
    } else {
        response.sendHeader(404);
    }
}).listen(8000);


// Server state
var clientPositions = {};  // clientId -> {x: y:}
var width = 0;
var height = 0;
var map = "";  // width X height tile ids (bytes)


fs.readFile("/Users/amitp/Projects/mapgen2/output.map", 'binary', function (err, data) {
    if (err) throw err;
    width = binaryToInt32LittleEndian(data.substr(0, 4));
    height = binaryToInt32LittleEndian(data.substr(4, 8));
    sys.log("Map size: " + width + ", " + height);
    map = data.substr(8);
});


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
        sys.log("+" + (thisLogTime - lastLogTime) + " socket[" + socket.remoteAddress + ":" + socket.remotePort + "] " + msg);
        lastLogTime = thisLogTime;
    }

    function sendMessage(message, binaryPayload /* optional */) {
        if (binaryPayload == null) binaryPayload = "";
        jsonMessage = JSON.stringify(message);
        log('sending ' + jsonMessage);
        socket.write(int32ToBinaryLittleEndian(jsonMessage.length)
                     + int32ToBinaryLittleEndian(binaryPayload.length));
        socket.write(jsonMessage);
        socket.write(binaryPayload);
    }
    
    function handleMessage(jsonMessage, binaryMessage) {
        log('handle message ' + jsonMessage);
        try {
            message = JSON.parse(jsonMessage);  // TODO: move out?
        } catch (e) {
            log('error ' + e.message + ' while parsing: ' + JSON.stringify(jsonMessage));
            return;
        }
        
        if (message.type == 'mouse_move') {
            // NOTE: we're temporarily using remotePort as the client id
            clientPositions[socket.remotePort] = {x: message.x, y: message.y};
        } else if (message.type == 'ping') {
            respondWithGlobalState(message.timestamp);
        } else if (message.type == 'map_tiles') {
            respondWithMapTiles(message.timestamp,
                                message.left, message.right,
                                message.top, message.bottom);
        } else {
            log('  -- unknown message type');
        }
    }

    function respondWithMapTiles(clientTimestamp, left, right, top, bottom) {
        var tiles = [];
        for (var x = left; x <= right; x++) {
            tiles.push(map.slice(x*height + top, x*height + bottom+1));
        }
        log('output:', tiles);
        sendMessage({
            type: 'map_tiles',
            timestamp: clientTimestamp,
            left: left,
            right: right,
            top: top,
            bottom: bottom,
            tiles: tiles
        });
    }
    
    function respondWithGlobalState(clientTimestamp) {
        sendMessage({
            type: 'all_positions',
            timestamp: clientTimestamp,
            positions: clientPositions
        });
    }
    
    socket.setEncoding("binary");
    socket.setNoDelay();
    
    socket.addListener("connect", function () {
        log("connect");
    });
    socket.addListener("data", function (data) {
        if (bytesRead == 0 && data == "<policy-file-request/>\0") {
            log("policy-file-request");
            socket.write(crossdomainPolicy);
            socket.close();
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
                    socket.close();
                    return;
                }
                if (!(0 <= binaryLength && binaryLength <= 10000000)) {
                    log("ERROR: binaryLength corrupt? ", binaryLength);
                    socket.close();
                    return;
                }

                if (buffer.length >= 8 + jsonLength + binaryLength) {
                    // We have the message, so process it, and remove those bytes
                    handleMessage(buffer.substr(8, jsonLength),
                                  buffer.substr(8 + jsonLength, binaryLength));
                    buffer = buffer.slice(8 + jsonLength + binaryLength);
                } else {
                    // We don't have a full message, so wait
                    break;
                }
            }
        }
    });
    socket.addListener("end", function () {
        log("end");
        // TODO: need to track this socket's id, and remove from clientPositions here, or on timeout
        delete clientPositions[socket.remotePort];
        socket.close();
    });
}).listen(8001);

sys.log('Servers running at http://127.0.0.1:8000/ and tcp:8001');
