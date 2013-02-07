mongoose = require 'mongoose'
Schema   = mongoose.Schema

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
ProgTime = mongoose.model("ProgTime", ProgTimeSchema)

module.exports = { ProgTime }
