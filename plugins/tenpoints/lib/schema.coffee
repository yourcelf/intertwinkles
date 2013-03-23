mongoose  = require 'mongoose'
Schema    = mongoose.Schema

load = (config) ->
  TenPointSchema = new Schema
    name: {type: String, required: true}
    slug: {type: String, required: true, unique: true}
    created: {type: Date, default: Date.now}
    sharing: {
      group_id: String
      public_view_until: Date
      public_edit_until: Date
      extra_viewers: [String]
      extra_editors: [String]
      advertise: Boolean
    }
    points: [{
      revisions: [{
        text: String
        created: {type: Date, default: Date.now}
        supporters: [{
          user_id: {type: Schema.ObjectId, ref: 'User'}
          name: String
          date: {type: Date, default: Date.now}
        }]
      }]
    }]
  TenPointSchema.virtual('url').get ->
    return "/10/#{@slug}/"
  TenPointSchema.virtual('absolute_url').get ->
    return "#{config.apps.tenpoints.url}#{@url}"

  schemas = {}
  for name, schema of {TenPoint: TenPointSchema}
    try
      schemas[name] = mongoose.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)
  return schemas

module.exports = { load }
