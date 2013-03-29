#!/usr/bin/env node

require("coffee-script");
require("../plugins/points/lib/import_old_tenpoints").run(
    require("../config/config"), "/tmp/old_tenpoints.json")
