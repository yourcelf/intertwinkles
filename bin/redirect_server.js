#!/usr/bin/env node

require("coffee-script");
var config = require("../config/config");
var http = require("http")
var server = http.createServer(function (req, res) {
    res.writeHead(301, {
      "Location": config.api_url + req.url,
      "Expires":  (new Date).toGMTString()
    });
    res.end();
});
server.listen(config.redirect_port || 9002)
