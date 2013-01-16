_           = require 'underscore'
icons       = require './icons'
async       = require 'async'
solr        = require 'solr-client'
querystring = require 'querystring'
url         = require 'url'
logger      = require('log4js').getLogger()

route = (config, app) ->
  schema = require('./schema').load(config)
  solr_client = solr.createClient(config.solr)
  solr_client.autoCommit = true

  solr_escape = (query) ->
    # List of special chars: 
    # https://lucene.apache.org/core/4_0_0/queryparser/org/apache/lucene/queryparser/classic/package-summary.html#Escaping_Special_Characters
    return query.replace(/[-+&|!(){}\[\]^"~*?:\\\/]/mg, "\\$1")

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

  get_user = (req, res, query, fn) ->
    if query?
      if query.indexOf('@') != -1
        filter = {email: query}
      else
        filter = {_id: query}
      schema.User.findOne filter, (err, doc) ->
        return server_error(res, err) if err?
        unless doc?
          res.statusCode = 404
          return res.send {error: "No user found for '#{query}'", status: 404}
        return fn({model: doc})
    else
      res.statusCode = 403
      res.send({error: "User not specified", status: res.statusCode})

  # Method for retrieving users who are logging in. Process email change
  # requests, and create user object if the user is not found.
  log_email_in = (req, res, fn, method='GET') ->
    query = if method == 'GET' then req.query else req.body
    email = query.user
    if email?
      schema.User.findOne {$or: [{email: email}, {email_change_request: email}]}, (err, doc) ->
        if err? then return server_error(res, err)
        if doc?
          # Email recognized. Return the user object.
          if not doc.joined?
            # This is the first time they've logged in; but they've been previously invited.
            logger.log "First time login", doc
            doc.set("joined", new Date())
            doc.save (err, doc) ->
              fn({model: doc, message: "NEW_ACCOUNT"})
          else if doc.email_change_request == email
            # Process a change of email request.  Assume the email has already
            # been validated by persona.
            doc.set("email", email)
            doc.set("email_change_request", null)
            doc.save (err, doc) ->
              fn({model: doc, message: "CHANGE_EMAIL"})
          else
            fn({model: doc})
        else
          # Unknown user. Create a new account for them with random icon.
          logger.warn "Unknown user, creating"
          doc = new schema.User({email: email, name: "", joined: new Date()})
          doc.save (err, doc) ->
            if err? then return server_error(res, err)
            fn({model: doc, message: "NEW_ACCOUNT"})

    else
      res.statusCode = 403
      res.send({error: "Unknown user", status: res.statusCode})

  app.get "/api/groups/", (req, res) ->
    return unless validate_request(req, res, ["user", "api_key"])
    log_email_in req, res, (data) ->
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
          get_user req, res, req.query.user, (data) ->
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
          get_user req, res, query_event.user, (data) ->
            done(null, data.model._id)
        else
          done(null, null)
      (done) ->
        if query_event.via_user?
          get_user req, res, query_event.via_user, (data) ->
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
    get_user req, res, req.body.user, (data) ->
      user = data.model
      user.name = req.body.name if req.body.name # exclude falsey things like ''
      if req.body.icon_id?
        user.icon.pk = req.body.icon_id if req.body.icon_id?
        user.icon.name = icons.get_icon_name(user.icon.pk)
      user.icon.color = req.body.icon_color if req.body.icon_color?
      user.mobile.number = req.body.mobile_number if req.body.mobile_number?
      user.mobile.carrier = req.body.mobile_carrier if req.body.mobile_carrier?
      user.save (err, doc) ->
        return server_error(res, err) if err?
        res.send {status: 200, model: user}

  app.get "/api/notifications/", (req, res) ->
    return unless validate_request(req, res, ["api_key", "user"], 'GET')
    get_user req, res, req.query.user, (data) ->
      user = data.model
      schema.Notification.find({
        recipient: user._id
        cleared: {$ne: true}
        suppressed: {$ne: true}
        "formats.web": {$ne: null}
      }).sort('-date').limit(51).exec (err, docs) ->
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
      for key in ["application", "entity", "type", "group"]
        if params[key]?
          notice_conditions[key] = params[key]
      for key in ["date", "url", "formats"]
        notice_update[key] = params[key] if params[key]?
      notice_update.cleared = false

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
    get_user req, res, req.body.user, (data) ->
      user = data.model
      schema.Notification.findOneAndUpdate({
        recipient: user._id
        _id: req.body.notification_id
      }, {suppressed: true}, {new: true, upsert: false}, (err, doc) ->
        return server_error(res, err) if err?
        res.send {notification: doc}
      )

  # Clear notifications: Mark them as complete. However, if they are updated,
  # they will be un-cleared.
  app.post "/api/notifications/clear", (req, res) ->
    return unless validate_request(req, res, ["api_key"], 'POST')

    if not (
        (req.body.notification_id? and req.body.user) or
        (req.body.application? and req.body.entity? and req.body.type?) or
        (req.body.group and (req.body.user or req.body.recipient)))
      res.statusCode = 400
      return res.send({
        error: "Notifications insufficiently specified. Requires either (user, " +
               "notification_id) or (application, entity, type) or (group, user)."
        status: 400
      })

    query = {}
    query._id = {$in: req.body.notification_id.split(",")} if req.body.notification_id?
    query.application = req.body.application if req.body.application?
    query.entity = req.body.entity if req.body.entity?
    query.type = req.body.type if req.body.type?
    query.group = req.body.group if req.body.group?
    query.recipient = req.body.recipient if req.body.recipient?

    async.series [
      (done) ->
        if req.body.user?
          get_user req, res, req.body.user, (data) ->
            query.recipient = data.model.id
            done(null)
        else
          done(null, null)
      (done) ->
        schema.Notification.find query, (err, docs) ->
          mark_cleared = (doc, cb) ->
            doc.cleared = true
            doc.save(cb)
          async.map docs, mark_cleared, (err, results) ->
            return server_error(res, err) if err?
            return res.send({notifications: results})
    ]

  app.get "/api/search/", (req, res) ->
    return unless validate_request(req, res, ["api_key"])
    if not req.query.user? and req.query.public != 'true'
      res.statusCode = 400
      return res.send({error: "Must set `public=true` or specify user"})

    query_and = []
    if req.query.q # exclude falsy strings like ""
      query_and.push(solr_escape(req.query.q))
    for param in ["application", "entity", "type"]
      if req.query[param]?
        obj = {}
        obj[param] = req.query[param]
        query_and.push(querystring.stringify(obj, "%20AND%20", ":"))

    async.waterfall [
      (done) ->
        return done(null, null) unless req.query.user?
        if req.query.user?.indexOf('@') != -1
          q = {email: req.query.user}
        else
          q = {_id: req.query.user}
        schema.User.findOne(q, (err, doc) -> done(err, doc))

      (user, done) ->
        if user?._id
          schema.Group.find {"members.user": user._id}, '_id', (err, groups) ->
            done(err, user, (solr_escape(g._id.toString()) for g in groups))
        else
          done(null, user, [])

      (user, groups, done) ->
        # Build that sharing awesomeness query.
        sharing_or = []
        if req.query.public == 'true'
          sharing_or.push("(sharing_advertise:true AND (" +
            "sharing_public_view_until:[NOW TO *] OR " +
            "sharing_public_edit_until:[NOW TO *]" +
          "))")
        if groups.length > 0
          sharing_or.push("sharing_group_id:(#{groups.join(" OR ")})")
        if user?.email?
          sharing_or.push("sharing_extra_editors:#{solr_escape(user.email)}")
          sharing_or.push("sharing_extra_viewers:#{solr_escape(user.email)}")
        if sharing_or.length == 0
          res.statusCode = 404
          return done("Bad user, groups, or public.")

        query_and.push("(#{sharing_or.join(" OR ")})")
        query = solr_client.createQuery()
        query.q(query_and.join(" AND "))
        query.set("hl=true")
        if req.query.sort?
          query.set("sort=#{querystring.stringify(solr_escape(req.query.sort))}")
        done(null, query)

    ], (err, query) ->
      if err?
        if res.statusCode == 404
          return res.send({error: "None found.", status: 404})
        else
          return server_error(res, err) if err?

      solr_client.search query, (err, obj) ->
        return server_error(res, err) if err?
        res.send(obj)

  app.post "/api/search/", (req, res) ->
    return unless validate_request(req, res, [
      "api_key", "application", "entity", "type", "url", "title", "summary", "text"
    ], 'POST')

    conditions = {}
    update = {}
    options = {upsert: true, 'new': true}

    for key in ["application", "entity", "type"]
      conditions[key] = req.body[key]

    for key in ["title", "summary", "text", "url"]
      update[key] = req.body[key]

    if req.body.sharing?
      update.sharing = req.body.sharing

    schema.SearchIndex.findOneAndUpdate conditions, update, options, (err, doc) ->
      return server_error(res, err) if err?
      res.send { searchindex: doc }
    
      solr_doc = {
        modified: new Date()
        sharing_group_id: doc.sharing?.group_id
        sharing_public_view_until: doc.sharing?.public_view_until
        sharing_public_edit_until: doc.sharing?.public_edit_until
        sharing_extra_viewers: doc.sharing?.extra_viewers?.join("\n")
        sharing_extra_editors: doc.sharing?.extra_editors?.join("\n")
        sharing_advertise: doc.sharing?.advertise == true
      }
      for key in ["application", "entity", "type", "url", "title", "summary", "text"]
        solr_doc[key] = doc[key]

      solr_client.add solr_doc, (err, res) ->
        logger.error(err, res) if err? or res.responseHeader.status != 0

  app.del  "/api/search/", (req, res) ->
    return unless validate_request(req, res, [
      "api_key", "application", "entity", "type"
    ], 'DELETE')
    conditions = {
      application: req.body.application
      entity: req.body.entity
      type: req.body.type
    }
    schema.SearchIndex.findOneAndRemove conditions, (err, doc) ->
      return server_error(res, err) if err?
      
      solr_client.delete "entity", conditions.entity, (err, obj) ->
        return server_error(res, err) if err?
        return server_error(res, obj) if obj.responseHeader.status != 0
        res.send { result: "OK" }

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
    unless config.apps[req.body.application]?
      return res.send({error: "Invalid application"})

    app_url = config.apps[req.body.application].url
    app_url_parts = url.parse(app_url)
    parts = url.parse(req.body.path)
    unless parts.path.substring(0, app_url_parts.path.length) == app_url_parts.path
      return res.send({error: "Application and URL don't match"})

    # The long path is only the part of the URL that follows the configured app
    # URL.  That way, we can change where the application lives, without
    # breaking short URLs.
    long_path = parts.path.substring(app_url_parts.path.length)
    
    async.waterfall [
      (done) ->
        schema.ShortURL.findOne {
          long_path: long_path
          application: req.body.application
        }, (err, doc) ->
          return done(err, doc) if err? or doc?
          short_doc = new schema.ShortURL({
            long_path: long_path
            application: req.body.application
          })
          short_doc.save(done)

    ], (err, short_doc) ->
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
