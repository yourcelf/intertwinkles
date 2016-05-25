mongoose = require("mongoose")
async = require("async")

run = (config, callback) ->
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )
  schema = require("../../../lib/schema").load(config)
  tp_schema = require("../lib/schema").load(config)
  padlib = require("../lib/padlib")(config)

  tp_schema.TwinklePad.find {}, (err, docs) ->
    all_pads = []
    async.map docs, (doc, done) ->
      json = doc.toJSON()
      all_pads.push(json)
      padlib.etherpad.getHTML {padID: json.pad_id}, (err, data) ->
        json.html = data.html
        if json.sharing.group_id
          schema.Group.findOne({
            _id: json.sharing.group_id
          }).populate('members.user').exec (err, group) ->
            json.group = group.toJSON()
            done()
        else
          done()
    , (err) ->
      console.log(JSON.stringify(all_pads, null, 2))
      db.disconnect(callback or (->))

module.exports = {run}
