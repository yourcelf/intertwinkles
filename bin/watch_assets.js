#!/usr/bin/env node

require("coffee-script")
require("../lib/build_assets").watch(__dirname + "/../builtAssets")
