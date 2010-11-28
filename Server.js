// Flash Game Server
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


// Ports:
var HTTP_PORT = 8000;
var GAME_PORT = 8001;

// The cross-domain policy file must be served to Flash before it's willing to use a socket
var crossdomainPolicy = (
    "<!DOCTYPE cross-domain-policy SYSTEM"
        + " \"http://www.adobe.com/xml/dtds/cross-domain-policy.dtd\">\n"
        + "<cross-domain-policy>\n"
        + "<site-control permitted-cross-domain-policies=\"master-only\"/>\n"
        + "<allow-access-from domain=\"*\" to-ports=\"8000,8001\"/>\n"
        + "</cross-domain-policy>\n");


// Conversion from int to little-endian 32-bit binary and back
function binaryToInt32LittleEndian(buffer) {
    return buffer.charCodeAt(0) | (buffer.charCodeAt(1) << 8) | (buffer.charCodeAt(2) << 16) | (buffer.charCodeAt(3) << 24);
}

function int32ToBinaryLittleEndian(value) {
    return String.fromCharCode(value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff);
}


// First server is HTTP, for serving the SWFs.  swfFilesToServe should
// be a map {'/path': 'filename.swf'}.
function createWebServer(port, swfFilesToServe) {
    function handler(request, response) {
        var log = "??";
        if (request.method == 'GET' && request.url == '/crossdomain.xml') {
            log = "200 OK/xml";
            response.writeHead(200, {
                'Content-Type': 'text/xml',
                'Content-Length': crossdomainPolicy.length
            });
            response.write(crossdomainPolicy);
            response.end();
        } else if (request.method == 'GET' && swfFilesToServe[request.url] != null) {
            log = "200 OK/swf";
            fs.readFile(swfFilesToServe[request.url],
                        'binary', function (err, data) {
                            if (err) throw err;
                            response.writeHead(200, {
                                'Content-Type': 'application/x-shockwave-flash',
                                'Content-Length': data.length
                            });
                            response.write(data, 'binary');
                            response.end();
                        });
        } else if (request.method == 'GET' && request.url.substr(0, 5) == 'http:') {
            // People from China are probing to see if server will act as a proxy
            log = "403 PROXY-HONEYPOT";
            response.writeHead(403, "Honeypot");
            response.write("Request from " + request.connection.remoteAddress + " has been logged.")
            response.end();
        } else {
            log = "404 HONEYPOT";
            response.writeHead(404, "Honeypot");
            response.write("Request from " + request.connection.remoteAddress + " has been logged.")
            response.end();
        }
        sys.log("HTTP " + log + " " + request.connection.remoteAddress + " " + request.method + " " + request.url);
    }
    
    http.createServer(handler).listen(port);
}


// Second server is plain TCP, for the game communication. It also has
// to serve the cross-domain policy file.  This class handles a
// network connection to the client.
function NetworkConnection(MessageHandler) {
    return function (socket) {
        var messageHandler;
        var connectionId = socket.remoteAddress + ":" + socket.remotePort;
        var bytesRead = 0;
        var buffer = "";
        
        var lastLogTime = new Date().getTime();
        function log(msg) {
            var thisLogTime = new Date().getTime();
            sys.log("+" + (thisLogTime - lastLogTime) + " socket" + (socket.readyState == 'open'? "" : "."+socket.readyState) + "[" + socket.remoteAddress + ":" + socket.remotePort + "] " + msg);
            lastLogTime = thisLogTime;
        }
        
        function sendMessage(message, binaryPayload /* optional */) {
            if (binaryPayload == null) binaryPayload = "";
            jsonMessage = JSON.stringify(message);
            if (message.type != 'pong' && message.type != 'player_positions') {
                log('sending ' + message.type + " / " + jsonMessage.length + " / " + binaryPayload.length + " " + jsonMessage);
            }
            // Put everything into one string because we don't want to
            // create unnecessary packets with TCP_NODELAY. TODO: batch up
            // all messages written during handleMessage and send them all
            // at once.
            bytes = (int32ToBinaryLittleEndian(jsonMessage.length)
                     + int32ToBinaryLittleEndian(binaryPayload.length)
                     + jsonMessage
                     + binaryPayload);
            if (!socket.write(bytes, 'binary')) {
                log('BUFFER IS FULL ' + socket._writeQueue.length + " " + (socket._writeQueue.length > 0? socket._writeQueue[0].length : 0));
            }
        }
        
        
        socket.setEncoding("binary");
        socket.setNoDelay();
        
        socket.addListener("connect", function () {
            log("CONNECT");
            messageHandler = new MessageHandler(connectionId, log, sendMessage);
            
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
                            if (message.type != 'ping') log('handle message ' + message.type + jsonMessage);
                            messageHandler.handleMessage(message);
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
            messageHandler.handleDisconnect();
            socket.end();
        });
    };
}


exports.go = function(ClientHandler, swfFilesToServe) {
    createWebServer(HTTP_PORT, swfFilesToServe);
    net.createServer(NetworkConnection(ClientHandler)).listen(GAME_PORT);
    sys.log("Servers running at http://localhost:" + HTTP_PORT + "/ and tcp:" + GAME_PORT);
}

