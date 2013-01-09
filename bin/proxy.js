#!/usr/bin/env node

// Run the proxy server
require("coffee-script");
require("../lib/proxy").start(require("../config/proxy"));
