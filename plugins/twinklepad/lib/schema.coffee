mongoose       = require 'mongoose'
Schema         = mongoose.Schema
etherpadClient = require 'etherpad-lite-client'
async          = require 'async'
url            = require 'url'
uuid           = require 'node-uuid'

load = (config) ->
  pad_url_parts = url.parse(config.apps.twinklepad.etherpad.url)
  etherpad = etherpadClient.connect({
    apikey: config.apps.twinklepad.etherpad.api_key
    host: pad_url_parts.hostname
    port: pad_url_parts.port
  })

  TwinklePadSchema = new Schema
    pad_name: {type: String, required: true, unique: true}
    pad_id: {type: String}
    read_only_pad_id: {type: String}
    etherpad_group_id: {type: String}
    sharing: {
      group_id: String
      public_view_until: Date
      public_edit_until: Date
      extra_viewers: [String]
      extra_editors: [String]
      advertise: Boolean
    }

  TwinklePadSchema.pre 'save', (next) ->
    if @pad_id?
      next()
    else
      # Use the pad_name as the group mapper; one group per pad.
      async.series [
        (done) =>
          etherpad.createGroupIfNotExistsFor {
            groupMapper: encodeURIComponent(@pad_name)
          }, (err, data) =>
            @etherpad_group_id = data?.groupID
            done(err, data?.groupID)

        (done) =>
          etherpad.createGroupPad {
            groupID: @etherpad_group_id,
            padName: encodeURIComponent(@pad_name)
          }, (err, data) =>
            @pad_id = data?.padID
            return done(err, data)

      ], next
  TwinklePadSchema.pre 'save', (next) ->
    if @read_only_pad_id
      next()
    else
      etherpad.getReadOnlyID {
        padID: @pad_id
      }, (err, data) =>
        return next(err) if err?
        @read_only_pad_id = data.readOnlyID
        next()
  TwinklePadSchema.virtual('url').get ->
    "#{config.apps.twinklepad.etherpad.url}/p/#{@pad_id}"
  TwinklePadSchema.virtual('read_only_url').get ->
    "#{config.apps.twinklepad.etherpad.url}/p/#{@read_only_pad_id}"
  TwinklePadSchema.set('toObject', {virtuals: true})
  TwinklePadSchema.set('toJSON', {virtuals: true})

  schemas = {}
  for name, schema of {TwinklePad: TwinklePadSchema}
    try
      schemas[name] = mongoose.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)

  return schemas

module.exports = { load }
