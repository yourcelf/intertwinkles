_             = require 'underscore'
async         = require 'async'
url           = require 'url'
icons         = require './icons'
email_notices = require './email_notices'
logger        = require('log4js').getLogger()

module.exports = (config) ->
  schema = require("./schema").load(config)
  solr = require('./solr_helper')(config)

  # Private
  get_user = (query, callback) ->
    if query?
      if query.indexOf('@') != -1
        filter = {email: query}
      else
        filter = {_id: query}
      schema.User.findOne filter, callback
    else
      return callback("User not specified")

  # Collector for public methods
  m = {}
  
  #
  # Authentication and group data access
  #


  # Retrieve a user that is authenticating. Create the user if it doesn't
  # exist, and process any email change requests the user might have.
  m.get_authenticating_user = (email, callback) ->
    schema.User.findOne {$or: [{email: email}, {email_change_request: email}]}, (err, doc) ->
      if err? then return callback(err)
      if doc?
        # Email recognized. Return the user object.
        if not doc.joined?
          # This is the first time they've logged in; but they've been previously invited.
          logger.log "First time login", doc
          doc.set("joined", new Date())
          doc.save (err, doc) ->
            return callback(err, {user: doc, message: "NEW_ACCOUNT"})
        else if doc.email_change_request == email
          # Process a change-of-email request.  Assumes the email has already
          # been validated externally.
          doc.set("email", email)
          doc.set("email_change_request", null)
          doc.save (err, doc) ->
            return callback(err, {user: doc, message: "CHANGE_EMAIL"})
        else
          return callback(null, {user: doc})
      else
        # Unknown user. Create a new account for them with random icon.
        logger.warn "Unknown user, creating"
        doc = new schema.User({email: email, name: "", joined: new Date()})
        doc.save (err, doc) ->
          return callback(err, {user: doc, message: "NEW_ACCOUNT"})

  # Gets a list of the groups the given user belongs to, as well as a sanitized
  # list of users and invited members of each group suitable for display on the
  # client.
  _get_groups = (user, callback) ->
    output = {
      users: {}
      groups: {}
    }
    schema.Group.find({
      "members.user": user.id
    }).populate("members.user").populate("invited_members.user").exec (err, groups) ->
      return callback(err) if err?
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
      return callback(null, output)

  m.get_groups = (user, callback) ->
    if _.isObject(user)
      _get_groups(user, callback)
    else if _.isString(user)
      get_user user, (err, user) ->
        return callback(err) if err?
        _get_groups(user, callback)
    else
      callback("Unrecognized user, neither object nor string")

  m.verify_assertion = (assertion, callback) ->
    audience = url.parse(config.api_url).host
    browserid.verify assertion, audience, callback

  m.authenticate = (session, assertion, callback) ->
    m.verify_assertion assertion, (err, persona_response) ->
      return callback(err) if err?
      m.get_authenticating_user persona_response.email, (err, res) ->
        return callback(err) if err?
        { user, message } = res
        _get_groups user, (err, res) ->
          return callback(err) if err?
          { groups, users } = res
          session.auth = persona_response
          session.auth.user_id = user.id
          session.groups = groups
          session.users = users
          callback(err, session)

  m.clear_session_auth = (session, callback) ->
    session.auth = null
    session.groups = null
    session.users = null
    callback?(null, session)
    return session

  #
  # Short URLs
  #

  m.make_short_url = (user_url, application, callback) ->
    app_url = config.apps[application]?.url
    unless app_url?
      return callback("Invalid application")
    app_url_parts = url.parse(app_url)
    user_parts = url.parse(user_url)

    unless user_parts.path.substring(0, app_url_parts.path.length) == app_url_parts.path
      return callback("Application and URL don't match")

    # The long path we store is only the part of the URL that follows the
    # configured app URL.  That way, we can change where the application lives,
    # without breaking short URLs.
    long_path = user_parts.path.substring(app_url_parts.path.length)

    # Use find, save pattern rather than an upsert pattern, so that we get the
    # mongoose pre save triggers to fire.
    schema.ShortURL.findOne {
      long_path: long_path
      application: application
    }, (err, doc) ->
      return callback(err, doc) if err? or doc?
      short_doc = new schema.ShortURL({
        long_path: long_path
        application: application
      })
      short_doc.save (err, short_doc) ->
        callback(err, short_doc)

  #
  # Search indices
  #

  _add_search_index_timeout = {}
  _add_search_index = (params, callback) ->
    conditions = {}
    update = {}
    options = {upsert: true, 'new': true}
    for key in ["application", "entity", "type"]
      conditions[key] = params[key]
    for key in ["title", "summary", "text", "url"]
      update[key] = params[key]
    if params.sharing?
      update.sharing = params.sharing
    schema.SearchIndex.findOneAndUpdate conditions, update, options, (err, doc) ->
      return callback(err) if err?
      solr.post_search_index(doc, (err) -> callback(err, doc))

  m.add_search_index = (params, timeout, callback) ->
    if timeout and isNaN(timeout)
      callback = timeout
      timeout = null
    else
      callback or= (->)
      
    if timeout?
      key = [params.application, params.entity, params.type].join(":")
      if _add_search_index_timeout[key]?
        clearTimeout(_add_search_index_timeout[key])

      _add_search_index_timeout[key] = setTimeout ->
        logger.info "Posting timeout search index: ", key
        _add_search_index(params, callback)
      , timeout
    else
      _add_search_index(params, callback)

  m.remove_search_index = (application, entity, type, callback=(->)) ->
    schema.SearchIndex.findOneAndRemove {application, entity, type}, (err, doc) ->
      return callback(err) if err?
      solr.delete_search_index {entity}, (err) ->
        return callback(err) if err?
        callback(null)

  #
  # Notifications
  #

  m.get_notifications = (email, callback) ->
    get_user email, (err, user) ->
      return callback(err) if err?
      schema.Notification.find({
        recipient: user._id
        cleared: {$ne: true}
        suppressed: {$ne: true}
        "formats.web": {$ne: null}
      }).sort('-date').limit(51).exec(callback)

  m.clear_notifications = (params, callback=(->)) ->
    query = {}
    query._id = {$in: params.notification_id.split(",")} if params.notification_id?
    query.application = params.application if params.application?
    query.entity = params.entity if params.entity?
    query.type = params.type if params.type?
    query.recipient = params.recipient if params.recipient?
    async.series [
      (done) ->
        if params.user?
          get_user params.user, (err, doc) ->
            return callback(err) if err?
            query.recipient = doc.id
            done(null)
        else
          done(null, null)
      (done) ->
        schema.Notification.find query, (err, docs) ->
          mark_cleared = (doc, cb) ->
            doc.cleared = true
            doc.save (err, doc) ->
              cb(err, doc)
          async.map docs, mark_cleared, (err, results) ->
            callback(err, results)
    ]

  m.suppress_notifications = (email, notification_id, callback=(->)) ->
    get_user email, (err, user) ->
      return callback(err) if err?
      schema.Notification.findOneAndUpdate({
        recipient: user._id
        _id: notification_id
      }, {suppressed: true}, {new: true, upsert: false}, (err, doc) ->
        callback(err, doc)
      )

  m.post_notifications = (notices, callback=(->)) ->
    # Ensure we have required params for every notice.
    for params in notices
      missing = []
      for k in ["type", "url", "recipient", "formats"]
        missing.push(k) unless params[k]?
      if missing.length > 0
        return callback("Missing required parameters: #{missing.join(",")}")
      # Ensure we have correct "formats" 
      if not _.any([params.formats.web?, params.formats.sms?,
            (params.formats.email?.subject? and
            (params.formats.email?.body_text? or params.formats.email?.body_html?))])
        return callback(
          "Requires one or more of formats.web, formats.sms, or formats.email."
        )
    
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
        return callback(err) if err?
        unless results[0]?
          return callback("Sender '#{params.sender}' not found.")
        unless results[1]?
          return callback("Recipient '#{params.recipient}' not found.")

        # Save.
        if results[0] != false
          notice_conditions.sender = results[0]._id
        notice_conditions.recipient = results[1]._id
        options = {'new': true, 'upsert': true}
        schema.Notification.findOneAndUpdate(
          notice_conditions, notice_update, options, done
        )

    async.map(notices, store_notice, callback)

  #
  # Profiles
  #

  m.edit_profile = (params, callback=(->)) ->
    unless params.name
      return callback("Invalid name")
    if isNaN(params.icon_id)
      return callback("Invalid icon id #{data.model.icon.id}")
    get_user params.user, (err, user) ->
      return callback(err) if err?
      user.name = params.name if params.name?
      if params.icon_id?
        user.icon.pk = params.icon_id
        user.icon.name = icons.get_icon_name(user.icon.pk)
        user.icon.color = params.icon_color
      user.mobile.number = params.mobile_number if params.mobile_number?
      user.mobile.carrier = params.mobile_carrier if params.mobile_carrier?
      user.save(callback)

  #
  # Events
  #

  m.get_events = (params, callback) ->
    filter = {}
    async.parallel [
      (done) ->
        # Resolve email to user ID.
        if params.user?
          if /@/.test(params.user)
            get_user params.user, (err, user) ->
              return callback(err) if err?
              filter.user = user?._id
              done(null)
          else
            filter.user = params.user
        else
          done(null)
    ], (err, results) ->
      return callback(err) if err?
      # Date filter
      after = {date: {$gt: params.after}}
      before = {date: {$lt: params.before}}
      if params.after? and params.before?
        filter.date = { $and: [after, before] }
      else if params.after?
        filter.date = after
      else if params.before?
        filter.date = before
      schema.Event.find(filter, callback)

  _event_timeout_queue = {}
  _post_event = (params, callback) ->
    # Resolve user, group, via_user
    data = {}
    async.parallel [
      (done) ->
        if params.group?
          schema.Group.find {_id: params.group}, '_id', (err, group) ->
            data.group = group?._id
            done(err)
        else
          done(null)
      (done) ->
        if params.user?
          get_user params.user, (err, user) ->
            data.user = user?._id
            done(err)
        else
          done(null)
      (done) ->
        if params.via_user?
          get_user params.via_user, (err, user) ->
            data.via_user = user?._id
            done(err)
        else
          done(null)
    ], (err, results) ->
      return callback(err) if err?
      for key in ["application", "entity", "type", "entity_url", "date", "data"]
        data[key] = params[key] if params[key]?
      event = new schema.Event(data)
      event.save(callback)

  m.post_event = (params, timeout, callback=(->)) ->
    if timeout and isNaN(timeout)
      callback = timeout
      timeout = null
    else
      callback or= (->)
    if timeout?
      key = [
        params.application,
        params.entity,
        params.type,
        params.user,
        params.anon_id,
        params.group
      ].join(":")
    if _event_timeout_queue[key]
      return callback(null, _event_timeout_queue[key])

    _post_event params, (err, events) ->
      if timeout? and not err?
        _event_timeout_queue[key] = events
        setTimeout (-> delete _event_timeout_queue[key]), timeout
      return callback(err, events)

  #
  # Twinkles
  #

  m.get_twinkles = (params, callback) ->
    filter = {}
    for key in ["application", "entity", "url", "sender", "recipient"]
      filter[key] = params[key] if params[key]?
    schema.Twinkle.find(filter, callback)

  m.post_twinkle = (params, callback) ->
    conditions = {
      sender: params.sender or null
      sender_anon_id: params.sender_anon_id or null
      recipient: params.recipient or null
    }
    for key in ["application", "entity", "subentity", "url"]
      unless params[key]?
        return callback("Missing parameter `#{key}`")
      conditions[key] = params[key]
    unless params.sender? or params.sender_anon_id?
      return callback("Requires sender or sender_anon_id")

    update = {date: new Date()}
    options = {upsert: true, 'new': true}
    schema.Twinkle.findOneAndUpdate conditions, update, options, callback

  m.delete_twinkle = (params, callback) ->
    unless params.twinkle_id?
      return callback("Missing twinkle_id")
    conditions = {_id: params.twinkle_id}
    if params.entity
      conditions.entity = params.entity
    if params.sender?
      conditions.sender = params.sender
    else if params.sender_anon_id?
      conditions.sender_anon_id = params.sender_anon_id
    else
      return callback("Missing one of sender or sender_anon_id.")
    schema.Twinkle.findOneAndRemove conditions, callback
    
  return m
