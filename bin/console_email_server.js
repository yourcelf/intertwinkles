#!/usr/bin/env node

require("coffee-script");
var server = require("../dev/email_server")
server.start(server.consoleHandler)



