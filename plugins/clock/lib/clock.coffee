_ = require 'underscore'

module.exports = (config) ->
  schema = require("./schema").load(config)
  api_methods = require("../../../lib/api_methods")(config)
  c = {}

  c.post_event = (session, clock, type, opts) ->
    opts ?= {}
    event = _.extend {
      application: "clock"
      type: type
      entity_url: clock.url
      entity: clock.id
      user: session.auth?.user_id
      via_user: session.auth?.user_id
      anon_id: session.anon_id
      group: clock.sharing?.group_id
      data: {
        name: clock.name
        action: opts.data
      }
    }, opts.overrides or {}
    api_methods.post_event(event, opts.timeout or 0, opts.callback or (->))
  return c
