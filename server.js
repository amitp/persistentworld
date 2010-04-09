#!/usr/bin/env node

// Server for a Flash game

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

http.createServer(function (request, response) {
    if (request.method == "GET" && request.url == "/crossdomain.xml") {
      response.sendHeader(200, {'Content-Type': 'text/xml'});
      response.write(crossdomainPolicy);
      response.close();
    } else {
      response.sendHeader(200, {'Content-Type': 'text/plain'});
      response.write('Hello World. ' + JSON.stringify(request.url));
      response.close();
    }
}).listen(8000);

net.createServer(function (socket) {
    socket.setEncoding("binary");
    socket.addListener("connect", function () {
        socket.write("hello\r\n");
      });
    socket.addListener("data", function (data) {
        socket.write(JSON.stringify(data)+"\r\n");
      });
    socket.addListener("end", function () {
        socket.write("goodbye\r\n");
        socket.close();
      });
  }).listen(8001, "localhost");
sys.puts('Server running at http://127.0.0.1:8000/ and tcp:8001');
