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
    api_methods.retrieve_authenticating_user req.query.user, (err, data) ->
      return server_error(res, err) if err?
      user = data.model
      output = {
        user_id: user.id
        message: data.message
        users: {}
        groups: {}
      }
      output.users[user.id] = user

      schema.Group.find({
        "members.user": user.id
      }).populate("members.user").populate("invited_members.user").exec (err, groups) ->
        if err? then return server_error(res, err)
        for group in groups or []
          for member in group.members
            output.users[member.user.id] = member.user
            member.user = member.user.id
          for member in group.invited_members
            if not output.users[member.user.id]?
              u = member.user
              output.users[member.user.id] = {_id: u.id, id: u.id, email: u.email}
              member.user = u.id
          output.groups[group.id] = group
        res.send(output)

  app.get "/api/events/", (req, res) ->
    return unless validate_request(req, res, ["api_key"])
    try
      query_event = JSON.parse(req.query.event)
    catch e
      res.statusCode = 400
      return res.send({error: "Invalid JSON for `event`", statusCode: 400})

    async.parallel [
      (done) ->
        if query_event.user? and /@/.test(req.query.user)
          retrieve_user req, res, req.query.user, (data) ->
            query_event.user = data.model?._id
            done(null)
        else
          done(null)
    ], (err, results) ->
      # Date filter
      after = {date: {$gt: query_event.after}}
      before = {date: {$lt: query_event.before}}
      if query_event.after? and query_event.before?
        query_event.date = { $and: [after, before] }
      else if query_event.after?
        query_event.date = after
      else if query_event.before?
        query_event.date = before
      delete query_event.after
      delete query_event.before

      schema.Event.find query_event, (err, docs) ->
        return server_err(res, err) if err?
        res.send({events: docs})

  app.post "/api/events/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "event"], 'POST')
    query_event = req.body.event

    # Resolve user, group, via_user
    async.parallel [
      (done) ->
        if query_event.group?
          schema.Group.find {_id: query_event.group}, '_id', (err, group) ->
            done(err, group?._id)
        else
          done(null, null)
      (done) ->
        if query_event.user?
          retrieve_user req, res, query_event.user, (data) ->
            done(null, data.model._id)
        else
          done(null, null)
      (done) ->
        if query_event.via_user?
          retrieve_user req, res, query_event.via_user, (data) ->
            done(null, data.model._id)
        else
          done(null, null)
    ], (err, results) ->
      return server_error(res, err) if err?
      [group, user, via_user] = results
      query_event.group = group
      query_event.user = user
      query_event.via_user = via_user
      event = new schema.Event(query_event)
      event.save (err, doc) ->
        return server_error(res, err) if err?
        return res.send {event: doc}

  app.post "/api/profiles/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "user"], 'POST')
    query = {}
    for key in ["user", "name", "icon_id", "icon_color",
                "mobile_number", "mobile_carrier"]
      if req.body[key]?
        query[key] = req.body[key]
    api_methods.edit_profile query, (err, doc) ->
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

    for params in notice_params
      # Ensure we have required params
      missing = []
      for k in ["type", "url", "recipient", "formats"]
        missing.push(k) unless params[k]?
      if missing.length > 0
        res.statusCode = 400
        return res.send({
          error: "Missing required parameters: #{missing.join(",")}"
          statusCode: 400
        })
      # Ensure we have correct "formats"
      if not _.any([params.formats.web?, params.formats.sms?,
            (params.formats.email?.subject? and
            (params.formats.email?.body_text? or params.formats.email?.body_html?))])
        res.statusCode = 400
        return res.send({
          error: "Requires one or more of formats.web, formats.sms, or formats.email."
          statusCode: 400
        })

    store_notice = (params, done) ->
      # Prepare conditions and updates for posting to mongo. Any fields in
      # "conditions" will be used to determine whether this is a new notification
      # or a repeat. Fields in "update" will be updated (they are allowed to
      # change without creating a new notification).
      notice_conditions = {}
      notice_update = {}
      for key in ["application", "entity", "type"]
        if params[key]?
          notice_conditions[key] = params[key]
      for key in ["date", "url", "formats"]
        notice_update[key] = params[key] if params[key]?
      notice_update.cleared = false
      notice_update.date = new Date() unless notice_update.date?

      # Add user id's
      async.parallel [
        (done) ->
          done(null, false) unless params.sender?
          if params.sender.indexOf('@') != -1
            schema.User.findOne {email: params.sender}, (err, doc) -> done(err, doc)
          else
            done(null, {_id: params.sender})
        (done) ->
          if params.recipient.indexOf('@') != -1
            schema.User.findOne {email: params.recipient}, (err, doc) -> done(err, doc)
          else
            done(null, {_id: params.recipient})
      ], (err, results) ->
        return server_error(res, err) if err?
        unless results[0]?
          res.statusCode = 404
          return res.send({error: "Sender '#{params.sender}' not found.", status: 404})
        unless results[1]?
          res.statusCode = 404
          return res.send({error: "Recipient '#{params.recipient}' not found.", status: 404})

        # Save.
        if results[0] != false
          notice_conditions.sender = results[0]._id
        notice_conditions.recipient = results[1]._id
        options = {'new': true, 'upsert': true}
        schema.Notification.findOneAndUpdate(
          notice_conditions, notice_update, options, done
        )

    async.map notice_params, store_notice, (err, results) ->
      return server_error(res, err) if err?
      res.send {
        'notifications': results
      }

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
    solr.execute_search req.query, req.query.user, (err, obj) ->
      if err?
        logger.debug(err)
        return server_error(res, err)
      res.send(obj)

  app.post "/api/search/", (req, res) ->
    return unless validate_request(req, res, [
      "api_key", "application", "entity", "type", "url", "title", "summary", "text"
    ], 'POST')
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
    filter = {}
    for param in ["application", "entity", "url", "sender", "recipient"]
      if param in req.query?
        filter.param = req.query[param]
    schema.Twinkle.find filter, (err, docs) ->
      return server_error(res, err) if err?
      res.send { twinkles: docs }

  app.post "/api/twinkles/", (req, res) ->
    params = ["application", "entity", "subentity", "url"]
    return unless validate_request(req, res, ["api_key"].concat(params), 'POST')
    unless req.body.sender? or req.body.sender_anon_id?
      return server_error("Requires sender or sender_anon_id")

    conditions = {
      sender: req.body.sender or null
      sender_anon_id: req.body.sender_anon_id or null
      recipient: req.body.recipient or null
    }
    for param in params
      conditions[param] = req.body[param]
    update = {date: new Date()}
    options = {upsert: true, 'new': true}

    schema.Twinkle.findOneAndUpdate conditions, update, options, (err, doc) ->
      return server_error(res, err) if err?
      return res.send {twinkle: doc}

  app.del "/api/twinkles/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "twinkle_id"], 'DELETE')
    conditions = {_id: req.body.twinkle_id}
    conditions.entity = req.body.entity if conditions.entity?
    if req.body.sender?
      conditions.sender = req.body.sender
    else if req.body.sender_anon_id?
      conditions.sender_anon_id = req.body.sender_anon_id
    else
      res.statusCode = 400
      return res.send({error: "Requires sender or sender_anon_id"})
    schema.Twinkle.findOneAndRemove conditions, (err, doc) ->
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

  app.get "/r/:shortpath", (req, res) ->
    schema.ShortURL.findOne { short_path: req.params.shortpath }, (err, doc) ->
      return server_error(res, err) if err?
      return res.send("Not found", 404) unless config.apps[doc.application]?
      res.redirect(doc.absolute_long_url)

module.exports = {route}
