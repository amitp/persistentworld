// Server for a Flash game
// amitp@cs.stanford.edu
// License: MIT

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

    function handleMessage(msg) {
        log('handle message ' + JSON.parse(msg));
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
            log("data:" + data.length + " buffer:" + buffer.length);
            bytesRead += data.length;
            buffer += data;

            var checkEom = buffer.indexOf('\0');
            while (checkEom >= 0) {
                if (checkEom > 0) {
                    handleMessage(buffer.slice(0, checkEom));
                }
                buffer = buffer.slice(checkEom+1);
                checkEom = buffer.indexOf('\0');
            }
            socket.write(JSON.stringify({response: 'ok'})+'\0'+JSON.stringify({second: 'ok'}));
            setTimeout(function () {
                socket.write('\0');
            }, 300);
        }
    });
    socket.addListener("end", function () {
        log("end");
        socket.close();
    });
}).listen(8001, "localhost");

sys.log('Servers running at http://127.0.0.1:8000/ and tcp:8001');
