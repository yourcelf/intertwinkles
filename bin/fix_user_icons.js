#!/usr/bin/env node

require('coffee-script');
var config = require("../config/config")
var mongoose = require("mongoose");
var fix_icons = require("../lib/fix_icons")
var logger = require("log4js").getLogger()
var db = mongoose.connect(
    "mongodb://" + config.dbhost + ":" + config.dbport + "/" + config.dbname
);

fix_icons(config, function(err) {
    if (err) {
        logger.error(err)
    } else {
        logger.info("Finished.")
    }
    db.disconnect()
});
