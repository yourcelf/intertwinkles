#!/usr/bin/env node

// Generate fake data.  This uses the default config and database, not the test
// config, so the loaded data will appear on your development or production
// site.

require("coffee-script");
require("../test/factory").run(require("../config/config"));
