#!/usr/bin/env node

// Run the InterTwinkles web server.
require("coffee-script");
require("../lib/server").start(require("../config/config"));
