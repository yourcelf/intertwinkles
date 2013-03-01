mongoose  = require 'mongoose'
Schema    = mongoose.Schema

load = (config) ->

  ProposalSchema = new Schema
    resolved: Date
    passed: Boolean

    revisions: [{
      user_id: String
      name: String
      date: Date
      text: {type: String, required: true}
    }]

    opinions: [{
      user_id: String
      name: String
      revisions: [{
        vote: {
          type: String,
          required: true,
          enum: "yes weak_yes discuss no block abstain".split(" ")
        }
        text: String
        date: Date
      }]
    }]

    sharing: {
      group_id: String
      public_view_until: Date
      public_edit_until: Date
      extra_viewers: [String]
      extra_editors: [String]
      advertise: Boolean
    }
  ProposalSchema.pre 'save', (next) ->
    for rev in @revisions
      rev.date = new Date() unless rev.date?
    for opinion in @opinions
      for rev in opinion.revisions
        rev.date = new Date() unless rev.date?
    next()
  ProposalSchema.virtual('title').get ->
    parts = @revisions[0].text.split(" ")
    if parts.length < 20
      return @revisions[0].text
    return parts.slice(0, 20).join(" ") + "..."
  ProposalSchema.virtual('url').get -> "/p/#{@_id}"
  ProposalSchema.virtual('absolute_url').get ->
    return "#{config.apps.resolve.url}#{@url}"

  schemas = {}
  for name, schema of {Proposal: ProposalSchema}
    try
      schemas[name] = mongoose.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)

  return schemas

module.exports = { load }
