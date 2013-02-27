#!/usr/bin/env node

require("coffee-script");
require("../plugins/twinklepad/bin/resync_etherpad_ids").run(require("../config/config"))
