#!/usr/bin/env node

require("coffee-script");
var mongoose = require("mongoose");
var config = require("../config/config");
var notifier = require("../lib/email_notices").load(config);
var logger = require("log4js").getLogger();
var db = mongoose.connect(
    "mongodb://" + config.dbhost + ":" + config.dbport + "/" + config.dbname
);
notifier.send_daily_activity_summaries(function(err, sent_count) {
    if (err) { logger.error(err) }
    logger.info("Sent " + sent_count + " activity summaries.");
    db.disconnect();
});
