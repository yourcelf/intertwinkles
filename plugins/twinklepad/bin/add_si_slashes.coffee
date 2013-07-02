url = require "url"
async = require "async"
mongoose = require "mongoose"
etherpadClient = require "etherpad-lite-client"
logger = require('log4js').getLogger()

run = (config, callback) ->
  ###
  Goals:
  0. Ensure that TwinklePad pad names are synced up with groupIDs and padIDs.
  1. If there are any mongodb TwinklePad instances without corresponding
  etherpad instances, create the etherpads.
  2. If there are any etherpad instances without corresponding TwinklePad's,
  create the twinklepad's.
  ###
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )
  schema = require("../../../lib/schema").load(config)

  count = 0
  schema.SearchIndex.find {application: 'twinklepad'}, (err, docs) ->
    async.map docs, (doc, done) ->
      if doc.url.substring(doc.url.length - 1) != "/"
        new_url = doc.url + "/"
        logger.debug doc.url + " => " + new_url
        doc.url = new_url
        count += 1
        doc.save (err) ->
          done(err)
      else
        done(null)

    , (err) ->
      logger.error(err) if err?
      logger.info "Updated #{count} urls."
      db.disconnect(callback or (->))

module.exports = {run}
