_         = require 'underscore'
mongoose  = require 'mongoose'
Schema    = mongoose.Schema

load = (config) ->

  Point = {
    editing: [String]
    revisions: [{
      text: String
      created: {type: Date, default: Date.now}
      supporters: [{
        user_id: {type: Schema.ObjectId, ref: 'User'}
        name: String
        date: {type: Date, default: Date.now}
      }]
    }]
  }
  PointSetSchema = new Schema
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
    trash: Boolean
    points: [Point]
    drafts: [Point]
  PointSetSchema.virtual('title').get -> @name or 'Untitled'
  PointSetSchema.virtual('url').get ->
    return "/u/#{@slug}/"
  PointSetSchema.virtual('absolute_url').get ->
    return "#{config.apps.points.url}#{@url}"
  PointSetSchema.set('toObject', {virtuals: true})
  PointSetSchema.set('toJSON',   {virtuals: true})
  PointSetSchema.methods.find_point = (id) ->
    point = _.find(@points, (p) -> p._id.toString() == id.toString()) or \
            _.find(@drafts, (p) -> p._id.toString() == id.toString())
  PointSetSchema.methods.is_approved = (point) ->
    return not not _.find(@points, (p) -> p._id.toString() == point._id.toString())

  schemas = {}
  for name, schema of {PointSet: PointSetSchema}
    try
      schemas[name] = mongoose.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)
  return schemas

module.exports = { load }
