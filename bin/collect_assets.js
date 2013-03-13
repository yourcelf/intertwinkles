#!/usr/bin/env node

require("coffee-script")
require("../lib/collect_assets").compile_all(__dirname + "/../builtAssets")
