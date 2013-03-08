#!/usr/bin/env node

require("coffee-script")
require("../lib/build_assets").compile_all(__dirname + "/../builtAssets")
