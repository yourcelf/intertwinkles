mongoose    = require 'mongoose'
Schema      = mongoose.Schema
_           = require 'underscore'

load = (config) ->

  ResponseSchema = new Schema
    firestarter_id: {type: Schema.ObjectId, ref: 'Firestarter'}
    created: Date
    response: String
    user_id: String
    name: String
  ResponseSchema.pre 'save', (next) ->
    @set('created', new Date().getTime()) unless @created
    next()

  FirestarterSchema = new Schema
    created: Date
    modified: Date
    sharing: {
      group_id: String
      public_view_until: Date
      public_edit_until: Date
      extra_viewers: [String]
      extra_editors: [String]
      advertise: Boolean
    }
    slug: {type: String, unique: true, required: true}
    name: {type: String, required: true}
    prompt: {type: String, required: true}
    responses: [{type: Schema.ObjectId, ref: 'Response'}]
    public: Boolean
  FirestarterSchema.pre 'save', (next) ->
    @set('created', new Date().getTime()) unless @created
    @set('modified', new Date().getTime())
    next()

  schemas = {}
  for name, schema of {Firestarter: FirestarterSchema, Response: ResponseSchema}
    try
      schemas[name] = mongoose.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)

  #TODO: Make a property of the schema object.
  schemas.Firestarter.with_responses = (constraint, cb) ->
    schemas.Firestarter.findOne(constraint).populate('responses').exec(cb)

  return schemas

module.exports = { load }
