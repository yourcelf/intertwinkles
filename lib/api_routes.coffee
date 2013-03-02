_             = require 'underscore'
icons         = require './icons'
async         = require 'async'
solr_helper   = require './solr_helper'
url           = require 'url'
email_notices = require './email_notices'
logger        = require('log4js').getLogger()

route = (config, app) ->
  schema = require('./schema').load(config)
  api_methods = require('./api_methods')(config)
  email_notices = require('./email_notices').load(config)
  solr = solr_helper(config)

  server_error = (res, err) ->
    logger.error(err)
    res.statusCode = 500
    res.send({error: err})

  get_ip_address = (req) ->
    x_forwarded_for = req.header("X-Forwarded-For", null)
    if x_forwarded_for?
      return x_forwarded_for.split(",")[0].trim()
    return req.socket.remoteAddress

  validate_request = (req, res, required_params, method='GET') ->
    # Validate requesting ip.
    unless _.contains(config.api_clients, get_ip_address(req))
      res.statusCode = 400
      res.send({error: "Unauthorized client"})
      return false

    # Validate API key
    query = if method == 'GET' then req.query else req.body
    for val in required_params
      if not query[val]
        res.statusCode = 400
        res.send({error: "Missing required param '#{val}'", status: res.statusCode})
        return false
    unless _.contains config.authorized_keys, query.api_key
      res.statusCode = 403
      res.send({error: "Missing or invalid API key", status: res.statusCode})
      return false
    return true

  retrieve_user = (req, res, query, fn) ->
    if query?
      if query.indexOf('@') != -1
        filter = {email: query}
      else
        filter = {_id: query}
      schema.User.findOne filter, (err, doc) ->
        return server_error(res, err) if err?
        unless doc?
          return res.send {error: "No user found for '#{query}'", status: 404}, 404
        return fn({model: doc})
    else
      res.statusCode = 403
      res.send({error: "User not specified", status: res.statusCode})

  app.get "/api/groups/", (req, res) ->
    return unless validate_request(req, res, ["user", "api_key"])
    return server_error("Unknown user") unless req.query.user?
    api_methods.get_groups req.query.user, (err, data) ->
      return server_error(res, err) if err?
      res.send(data)

  app.get "/api/events/", (req, res) ->
    return unless validate_request(req, res, ["api_key"])
    try
      params = JSON.parse(req.query.event)
    catch e
      res.statusCode = 400
      return res.send({error: "Invalid JSON for `event`", statusCode: 400})
    api_methods.get_events params, (err, docs) ->
      return server_err(res, err) if err?
      res.send({events: docs})

  app.post "/api/events/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "event"], 'POST')
    try
      query_event = JSON.parse(req.body.event)
    catch e
      return res.send({error: "Invalid JSON for `event`", statusCode: 400}, 400)
    api_methods.post_event query_event, (err, doc) ->
      return server_error(res, err) if err?
      return res.send {event: doc}

  app.post "/api/profiles/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "user"], 'POST')
    api_methods.edit_profile req.body, (err, doc) ->
      return server_error(res, err) if err?
      res.send {status: 200, model: doc}

  app.get "/api/notifications/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "user"], 'GET')
    api_methods.get_notifications req.query.user, (err, docs) ->
        return server_error(res, err) if err?
        res.send({
          notifications: docs
        })

  app.post "/api/notifications/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "params"], 'POST')
    notice_params = req.body.params
    unless notice_params.constructor == Array
      notice_params = [notice_params]
    api_methods.post_notifications notice_params, (err, docs) ->
      return server_error(res, err) if err?
      return res.send { notifications: docs }

  # Suppress notifications: Prevent their being shown, even if their event updates.
  app.post "/api/notifications/suppress", (req, res) ->
    return unless validate_request(req, res, ["api_key", "user", "notification_id"], 'POST')
    api_methods.suppress_notifications(
      req.body.user,
      req.body.notification_id,
      (err, doc) ->
        return server_error(res, err) if err?
        res.send {notification: doc}
    )

  # Clear notifications: Mark them as complete. However, if they are updated,
  # they will be un-cleared.
  app.post "/api/notifications/clear", (req, res) ->
    return unless validate_request(req, res, ["api_key"], 'POST')

    if not (
        (req.body.notification_id?) or
        (req.body.application? and req.body.entity? and req.body.type?) or
        (req.body.user or req.body.recipient))
      return res.send({
        error: "Notifications insufficiently specified. Requires either " +
               "(notification_id), (application, entity, type) or (user)."
      }, 400)

    api_methods.clear_notifications {
      notification_id: req.body.notification_id
      application: req.body.application
      entity: req.body.entity
      type: req.body.type
      recipient: req.body.recipient
    }, (err, notices) ->
      return server_error(res, err) if err?
      res.send({notifications: notices})

  app.get "/api/search/", (req, res) ->
    return unless validate_request(req, res, ["api_key"])
    if not req.query.user? and req.query.public != 'true'
      return res.send({error: "Must set `public=true` or specify user"}, 400)
    if req.query.public == 'true'
      req.query.public = true
    solr.execute_search req.query, req.query.user, (err, obj) ->
      if err?
        logger.debug(err)
        return server_error(res, err)
      res.send(obj)

  app.post "/api/search/", (req, res) ->
    return unless validate_request(req, res, [
      "api_key", "application", "entity", "type", "url", "title", "summary", "text"
    ], 'POST')
    if req.body.public == 'true'
      req.body.public = true
    api_methods.add_search_index req.body, (err, doc) ->
      return res.send {searchindex: doc}

  app.del "/api/search/", (req, res) ->
    return unless validate_request(req, res, [
      "api_key", "application", "entity", "type"
    ], 'DELETE')
    api_methods.remove_search_index(
      req.body.application,
      req.body.entity,
      req.body.type,
      (err) ->
        return server_error(res, err) if err?
        res.send { result: "OK" }
    )

  app.get "/api/twinkles/", (req, res) ->
    return unless validate_request(req, res, ["api_key"])
    api_methods.get_twinkles req.query, (err, docs) ->
      return server_error(res, err) if err?
      res.send { twinkles: docs }

  app.post "/api/twinkles/", (req, res) ->
    return unless validate_request(req, res, ["api_key"], 'POST')
    api_methods.post_twinkle req.body, (err, doc) ->
      return server_error(res, err) if err?
      return res.send {twinkle: doc}

  app.del "/api/twinkles/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "twinkle_id"], 'DELETE')
    api_methods.delete_twinkle req.body, (err) ->
      return server_error(res, err) if err?
      res.send {result: "OK", twinkle: {_id: req.body.twinkle_id}}

  #
  # URL shortening
  #
  app.post "/api/shorten/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "path", "application"], 'POST')
    api_methods.make_short_url req.body.path, req.body.application, (err, short_doc) ->
      return server_error(res, err) if err?
      res.send {
        short_url: short_doc.absolute_short_url
        long_url: short_doc.absolute_long_url
      }

module.exports = {route}
