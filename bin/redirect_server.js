#!/usr/bin/env node

require("coffee-script");
require("../lib/redirect_server").run(require("../config/config"));
