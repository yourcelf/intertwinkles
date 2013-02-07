#!/usr/bin/env node

require('coffee-script');
var config = require("../config/config")
var mongoose = require("mongoose");
var solr = require("../lib/solr_helper")(config)
var logger = require("log4js").getLogger()
var db = mongoose.connect(
    "mongodb://" + config.dbhost + ":" + config.dbport + "/" + config.dbname
);

solr.destroy_and_rebuild_solr_index(function(err, obj) {
    if (err) {
        logger.error(err);
    } else {
        logger.info(obj)
        logger.info("Complete.")
    }
    db.disconnect()
});


