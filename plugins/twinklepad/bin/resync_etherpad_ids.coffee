url             = require "url"
async           = require "async"
mongoose        = require "mongoose"
etherpadClient  = require "etherpad-lite-client"
logger          = require('log4js').getLogger()

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
  schema = require("../lib/schema").load(config)
  pad_url_parts = url.parse(config.apps.twinklepad.etherpad.url)
  etherpad = etherpadClient.connect({
    apikey: config.apps.twinklepad.etherpad.api_key
    host: pad_url_parts.hostname
    port: pad_url_parts.port
  })

  # As per the docs:
  # padID is `GROUPID$PADNAME`.
  # padName is the human readable name.
  # groupID is g.random; we give each pad 1 group.

  group_to_pad_name = {}
  pad_name_to_group = {}

  sync_etherpad_ids = (doc, done) ->
    ###
    Make sure that the given TwinklePad's pad_id and etherpad_group_id accord
    with etherpad's versions.  If not, fix them and resave the doc.
    ###
    if not doc.pad_name
      # This twinklepad is screwed up -- it doesn't have a name. We should
      # never be here.
      logger.error("Orphaned twinklepad missing pad_name: #{doc.id}")
      return done(null, null)
    else if not pad_name_to_group[doc.pad_name]
      # There's no etherpad with this name.  Nullify the groupID and padID and
      # re-save, so that we create one.
      logger.info("Etherpad for padName #{doc.pad_name} missing. Creating.")
      doc.pad_id = null
      doc.etherpad_group_id = null
      doc.save (err, doc) ->
        return done(err) if err?
        pad_name_to_group[doc.pad_name] = doc.etherpad_group_id
        group_to_pad_name[doc.etherpad_group_id] = doc.pad_name
        return done(null, doc)
    else if not doc.pad_id
      # This twinklepad wasn't saved right; it doesn't have a pad ID, but we
      # have an entry for its name. Correct the groupID and padID using
      # etherpad's versions.  Re-grab the read_only_pad_id to be sure.
      logger.info("Etherpad for padName #{doc.pad_name} missing. Creating.")
      doc.etherpad_group_id = pad_name_to_group[doc.pad_name]
      doc.pad_id = doc.etherpad_group_id + "$" + doc.pad_name
      doc.read_only_pad_id = null
      return doc.save (err, doc) ->
        console.log "WAI"
        if err?
          logger.error(err)
        else
          logger.info("done")
        done(err, doc)
    else if (group_to_pad_name[doc.etherpad_group_id] != doc.pad_name or
        pad_name_to_group[doc.pad_name] != doc.etherpad_group_id)
      # We have a padID, groupID, and padName, but they don't match.
      # Trust:
      # 1. TwinklePad's pad_name.
      # 2. Etherpad's groupID.
      logger.info("Pad name and group for #{doc.pad_name} don't match. Fixing.")
      doc.etherpad_group_id = pad_name_to_group[doc.pad_name]
      doc.pad_id = doc.etherpad_group_id + "$" + doc.pad_name
      doc.read_only_pad_id = null
      return doc.save(done)
    else
      return done(null, doc)


  async.waterfall [
    (done) ->
      # Fetch all etherpad groups.
      etherpad.listAllGroups {}, (err, data) ->
        return done(err) if err?
        return done(null, data.groupIDs)

    (groupIDs, done) ->
      # Fetch all group pad's.
      logger.debug("Fetching Group IDs")
      async.map(groupIDs, (groupID, done) ->
        etherpad.listPads {groupID}, (err, data) ->
          return done(err) if err?
          if data.padIDs.length != 1
            logger.error("Unexpectedly got #{data.padIDs.length} pad IDs for one group.")
            logger.error("Group ID", groupID)
            logger.error("Pad Names", group_to_pad_name[groupID])
            if data.padIDs.length > 0
              logger.error("Ignoring pads beyond first.")
          if data.padIDs.length > 0
            [group, name] = data.padIDs[0].split("$")
            group_to_pad_name[group] = name
            if pad_name_to_group[name]?
              logger.error("Unexpectedly found more than one pad named #{name}:")
              logger.error(pad_name_to_group[name], group)
            pad_name_to_group[name] = group
            logger.debug("found etherpad:", name, group)
          done()
      , done)

    (results, done) ->
      # Fix discrepencies in pad ID's.
      logger.debug("Fix discrepencies in pad ID's")
      schema.TwinklePad.find {}, (err, docs) ->
        logger.debug("found #{docs.length} twinklepads")
        async.map docs, sync_etherpad_ids, done

    (synced, done) ->
      # Create any missing TwinklePad instances.
      tps = {}
      for doc in synced
        continue unless doc?
        tps[doc.pad_name] = 1
      missing = (name for name, group of pad_name_to_group when not tps[name]?)
      async.map(missing, (name, done) ->
        logger.info("TwinklePad for #{name} not found. Creating.")
        group_id = pad_name_to_group[name]
        doc = new schema.TwinklePad({
          pad_name: name
          etherpad_group_id: group_id
          pad_id: group_id + "$" + name
        })
        doc.save(done)
      , done)

  ], (err) ->
    logger.error(err) if err?
    db.disconnect(callback or (->))

module.exports = {run}
