mongoose = require 'mongoose'
Schema   = mongoose.Schema

schema = null

load = (config) ->
  return schema if schema?
  schema = {}
  ProgTimeSchema = new Schema
    name: String
    created: Date
    sharing: {
      group_id: String
      public_view_until: Date
      public_edit_until: Date
      extra_viewers: [String]
      extra_editors: [String]
      advertise: Boolean
    }
    present: [{
      user_id: String
      name: String
    }]
    categories: [{
      name: String
      times: [{
        start: Date
        stop: Date
      }]
    }]
  ProgTimeSchema.pre 'save', (next) ->
    @set('created', new Date()) unless @created
    unless @categories?.length > 0
      @categories = [
        {name: "Female", times: []}
        {name: "Male", times: []}
        {name: "White", times: []}
        {name: "Person of Color", times: []}
      ]
    next()

  schemas = {}
  for name, schema of {ProgTime: ProgTimeSchema}
    try
      schemas[name] = mongoose.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)
  return schemas

module.exports = { load }
