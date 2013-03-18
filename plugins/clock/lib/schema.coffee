mongoose = require 'mongoose'
Schema   = mongoose.Schema

load = (config) ->
  ClockSchema = new Schema
    name: String
    about: String
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
      user_id: {type: Schema.ObjectId, ref: 'User'}
      name: String
    }]
    categories: [{
      name: String
      times: [{
        start: Date
        stop: Date
      }]
    }]
  ClockSchema.virtual('url').get ->
    return "/c/#{@_id}/"
  ClockSchema.virtual('absolute_url').get ->
    return "#{config.apps.clock.url}#{@url}"
  ClockSchema.pre 'save', (next) ->
    @set('created', new Date()) unless @created
    unless @categories?.length > 0
      @categories = [
        {name: "Female", times: []}
        {name: "Male", times: []}
        {name: "White", times: []}
        {name: "Person of Color", times: []}
      ]
    next()
  ClockSchema.set('toObject', {virtuals: true})
  ClockSchema.set('toJSON', {virtuals: true})

  schemas = {}
  for name, schema of {Clock: ClockSchema}
    try
      schemas[name] = mongoose.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)
  return schemas

module.exports = { load }
