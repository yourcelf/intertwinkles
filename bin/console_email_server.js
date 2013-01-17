#!/usr/bin/env node

require("coffee-script");
var server = require("../lib/email_server")
server.start(server.consoleHandler)



