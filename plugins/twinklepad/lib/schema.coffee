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
    # Non-unique human-readable name
    name: {type: String}
    # Slug, and unique etherpad name.
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
            if err?.message == "padName does already exist"
              @pad_id = @etherpad_group_id + "$" + encodeURIComponent(@pad_name)
              done(null)
            else if err?
              done(err)
            else
              @pad_id = data?.padID
              done(null)

      ], (err) ->
        throw new Error(err.message) if err?
        next()
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
    "/p/#{encodeURIComponent(@pad_name)}/"
  TwinklePadSchema.virtual('absolute_url').get ->
    config.apps.twinklepad.url + @url
  TwinklePadSchema.virtual('pad_url').get ->
    "#{config.apps.twinklepad.etherpad.url}/p/#{@pad_id}"
  TwinklePadSchema.virtual('read_only_url').get ->
    "#{config.apps.twinklepad.etherpad.url}/p/#{@read_only_pad_id}"
  TwinklePadSchema.virtual('title').get -> return @name or @pad_name
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
