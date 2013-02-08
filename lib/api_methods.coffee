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
  retrieve_user = (query, callback) ->
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
  # Retrieve a user that is authenticating. Create the user if it doesn't
  # exist, and process any email change requests the user might have.
  #
  m.retrieve_authenticating_user = (email, callback) ->
    schema.User.findOne {$or: [{email: email}, {email_change_request: email}]}, (err, doc) ->
      if err? then return callback(err)
      if doc?
        # Email recognized. Return the user object.
        if not doc.joined?
          # This is the first time they've logged in; but they've been previously invited.
          logger.log "First time login", doc
          doc.set("joined", new Date())
          doc.save (err, doc) ->
            return callback(err, {model: doc, message: "NEW_ACCOUNT"})
        else if doc.email_change_request == email
          # Process a change-of-email request.  Assumes the email has already
          # been validated externally.
          doc.set("email", email)
          doc.set("email_change_request", null)
          doc.save (err, doc) ->
            return callback(err, {model: doc, message: "CHANGE_EMAIL"})
        else
          return callback(null, {model: doc})
      else
        # Unknown user. Create a new account for them with random icon.
        logger.warn "Unknown user, creating"
        doc = new schema.User({email: email, name: "", joined: new Date()})
        doc.save (err, doc) ->
          return callback(err, {model: doc, message: "NEW_ACCOUNT"})

  m.retrieve_groups = (user, callback) ->
    output = {
      users: {}
      groups: {}
    }
    schema.Groups.find({
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

  m.add_search_index = (params, callback) ->
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
      callback(null, doc)
      solr.post_search_index(doc)

  m.remove_search_index = (application, entity, type, callback) ->
    schema.SearchIndex.findOneAndRemove {application, entity, type}, (err, doc) ->
      return callback(err) if err?
      solr.delete_search_index {entity}, (err) ->
        return callback(err) if err?
        callback(null)

  m.get_notifications = (email, callback) ->
    retrieve_user email, (err, user) ->
      return callback(err) if err?
      schema.Notification.find({
        recipient: user._id
        cleared: {$ne: true}
        suppressed: {$ne: true}
        "formats.web": {$ne: null}
      }).sort('-date').limit(51).exec(callback)

  m.clear_notifications = (params, callback) ->
    query = {}
    query._id = {$in: params.notification_id.split(",")} if params.notification_id?
    query.application = params.application if params.application?
    query.entity = params.entity if params.entity?
    query.type = params.type if params.type?
    query.recipient = params.recipient if params.recipient?
    async.series [
      (done) ->
        if params.user?
          retrieve_user params.user, (err, doc) ->
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

  m.suppress_notifications = (email, notification_id, callback) ->
    retrieve_user email, (err, user) ->
      return callback(err) if err?
      schema.Notification.findOneAndUpdate({
        recipient: user._id
        _id: notification_id
      }, {suppressed: true}, {new: true, upsert: false}, (err, doc) ->
        callback(err, doc)
      )

  m.edit_profile = (params, callback) ->
    unless params.name
      return callback("Invalid name")
    if isNaN(params.icon_id)
      return callback("Invalid icon id #{data.model.icon.id}")

    retrieve_user params.user, (err, user) ->
      return callback(err) if err?
      user.name = params.name if params.name?
      if params.icon_id?
        user.icon.pk = params.icon_id
        user.icon.name = icons.get_icon_name(user.icon.pk)
        user.icon.color = params.icon_color
      user.mobile.number = params.mobile_number if params.mobile_number?
      user.mobile.carrier = params.mobile_carrier if params.mobile_carrier?
      user.save(callback)
  
  return m
