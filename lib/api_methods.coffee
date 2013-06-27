_             = require 'underscore'
async         = require 'async'
url           = require 'url'
icons         = require './icons'
email_notices = require './email_notices'
persona       = require './persona_consumer'
utils         = require './utils'
logger        = require('log4js').getLogger()
deletion_notice_view = require("../emails/request_to_delete")

module.exports = (config) ->
  schema = require("./schema").load(config)
  solr = require('./solr_helper')(config)
  grammar_getters = {
    www: require("./www_events_grammar")
  }
  deletion_handlers = {}

  # Use 'do' to avoid putting 'key' in global namespace.
  do ->
    for key in _.keys(config.apps)
      continue if key == "www"
      grammar_getters[key] = require("../plugins/#{key}/lib/events_grammar")
      try
        deletion_handlers[key] = require("../plugins/#{key}/lib/deletion_handler")(config)
      catch e

  # Private
  get_user = (query, callback) ->
    if query?
      if query.toString().indexOf('@') != -1
        filter = {email: query}
      else
        filter = {_id: query}
      schema.User.findOne filter, callback
    else
      return callback("User not specified")

  # Collector for public methods
  api = {}
  
  #
  # Authentication and group data access
  #


  # Retrieve a user that is authenticating. Create the user if it doesn't
  # exist, and process any email change requests the user might have.
  api.get_authenticating_user = (email, callback) ->
    schema.User.findOne {$or: [{email: email}, {email_change_request: email}]}, (err, doc) ->
      if err? then return callback(err)
      if doc?
        # Email recognized. Return the user object.
        if not doc.joined?
          # This is the first time they've logged in; but they've been previously invited.
          logger.debug "First time login", doc
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
        logger.debug "Unknown user, creating"
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
      "$or": [{"members.user": user._id}, {"invited_members.user": user._id}]
    }).populate("members.user").populate("invited_members.user").exec (err, groups) ->
      return callback(err) if err?

      output.users[user.id] = user
      for group in groups or []
        # Are we a member of this group?
        if _.find(group.members, (m) -> m.user.id == user.id)
          # Add full details of each member of this group.
          for member in group.members
            output.users[member.user.id] = member.user
            member.user = member.user.id
          # Just include emails and user ID's for invitees.
          for member in group.invited_members
            if not output.users[member.user.id]?
              u = member.user
              output.users[member.user.id] = {_id: u.id, id: u.id, email: u.email}
              member.user = u.id
          output.groups[group.id] = group
        else
          # Not a member, we must be an invitee.  Just add the user who invited us.
          invitation = _.find(group.invited_members, (i) -> i.user.id == user.id)
          if invitation.invited_by?
            invitor_id = invitation.invited_by.toString()
            invitor = _.find(group.members, (m) -> m.user.id == invitor_id)
            if invitor?
              output.users[invitor_id] = invitor.user
      return callback(null, output)

  # Resolves the first argument into a user object, then gets the user's
  # associated groups.
  api.get_groups = (email_or_id_or_user, callback) ->
    if _.isObject(email_or_id_or_user)
      _get_groups(email_or_id_or_user, callback)
    else if _.isString(email_or_id_or_user)
      get_user email_or_id_or_user, (err, user) ->
        return callback(err) if err?
        _get_groups(user, callback)
    else
      callback("Unrecognized user, neither object nor string")

  api.verify_assertion = (assertion, callback) ->
    audience = url.parse(config.api_url).host
    persona.verify assertion, audience, callback

  api.authenticate = (session, assertion, callback) ->
    api.verify_assertion assertion, (err, persona_response) ->
      if err?
        err.assertion = assertion
        return callback(err)
      api.get_authenticating_user persona_response.email, (err, data) ->
        return callback(err) if err?
        { user, message } = data
        _get_groups user, (err, data) ->
          return callback(err) if err?
          { groups, users } = data
          session.auth = persona_response
          session.auth.user_id = user.id
          session.groups = groups
          session.users = users
          callback(err, session, message)

  api.clear_session_auth = (session, callback) ->
    session.auth = null
    session.groups = null
    session.users = null
    callback?(null, session)
    return session

  #
  # Short URLs
  #

  api.make_short_url = (user_url, application, callback) ->
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
    unless long_path.substring(0, 1) == "/"
      long_path = "/#{long_path}"

    # Use find + save pattern rather than an upsert pattern, so that we get the
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
  # Deletion
  #
  _delete_entity = (params, callback) ->
    handler = deletion_handlers[params.application]

    handler.delete_entity params, ->
      query = {
        application: params.application
        entity: params.entity
      }
      async.parallel [
        (done) -> schema.Event.find(query).remove (err) -> done(err)
        (done) ->
          schema.SearchIndex.findOne query, (err, si) ->
            api.remove_search_index(si.application, si.entity, si.type, done)
        (done) -> schema.Notification.find(query).remove (err) -> done(err)
        (done) -> schema.Twinkle.find(query).remove (err) -> done(err)
      ], (err) ->
        callback(err)

  _queue_deletion = (session, params, callback) ->
    schema.DeletionRequest.findOne {
      application: params.application, entity: params.entity
    }, (err, obj) ->
      return callback(err) if err?
      return callback(null, obj) if obj?
      handler = deletion_handlers[params.application]

      dr = new schema.DeletionRequest {
        application: params.application
        entity: params.entity
        entity_url: params.url
        group: params.group
        title: params.title
        start_date: new Date()
        # TODO: un-hardcode 3 day deletion window
        end_date: new Date(new Date().getTime() + 1000 * 60 * 60 * 24 * 3)
        confirmers: [session.auth.user_id]
      }
      async.parallel [
        (done) ->
          dr.save (err, dr) ->
            done(err, dr)
        (done) ->
          api.trash_entity session, {
            application: params.application, entity: params.entity,
            group: params.group, trash: true
          }, done


        (done) ->
          api.post_event {
            application: dr.application
            entity: dr.entity
            type: "deletion"
            url: dr.entity_url
            date: new Date()
            user: session.auth.user_id
            group: dr.group
            data: {
              end_date: dr.end_date
              entity_name: dr.title
            }
          }, (err, event) ->
            done(err, event)

      ], (err, results) ->
        return callback(err) if err?
        [dr, trashing, event] = results
        _update_deletion_notifications session, dr, (err, notices) ->
          return callback(null, dr, trashing, event, notices)

  _update_deletion_notifications = (session, dr, callback) ->
    {render_notifications} = email_notices.load(config)
    schema.Group.findOne {_id: dr.group}, (err, group) ->
      return callback(err) if err?
      async.series [
        (done) ->
          api.clear_notifications {
            entity: dr.entity
            type: "deletion"
          }, (err, notifications) ->
            return done(err) if err?
            return done(null, notifications or [])

        (done) ->
          member_ids = (m.user.toString() for m in group.members)
          confirmed = (id.toString() for id in dr.confirmers)
          needed = _.difference(member_ids, confirmed)

          render_notice = (user_id, cb) ->
            render_notifications deletion_notice_view, {
              group: dr.group
              sender: session.users[dr.confirmers[0]] or "A user"
              recipient: session.users[user_id]
              url: dr.url
              deletion_request: dr
            }, (err, rendered) ->
              return cb(err) if err?
              cb(null, {
                type: "deletion"
                entity: dr.entity
                recipient: user_id
                url: dr.url
                sender: dr.confirmers[0]
                application: "www"
                formats: rendered
              })
          async.map(needed, render_notice, done)

      ], (err, results) ->
        return callback(err) if err?
        [ clear_notices, new_notices ] = results
        return callback(null, clear_notices) if new_notices.length == 0
        api.post_notifications new_notices, (err, notifications) ->
          return callback(err) if err?
          return callback(null, clear_notices.concat(notifications))

  api.request_deletion = (session, params, callback) ->
    ###
    Request deletion.  If the receiving application's policy permits, delete
    immediately; otherwise, create a DeletionRequest and associated
    notifications.
    ###
    unless utils.is_authenticated(session)
      return callback("Permission denied")
    for key in ["group", "application", "entity", "url", "title"]
      unless params[key]
        return callback("Missing param #{key}")
    handler = deletion_handlers[params.application]
    return callback("Missing handler") unless handler?
    handler.can_delete session, params, (err, can_delete) ->
      return callback(err) if err?
      if can_delete == "delete"
        _delete_entity(params, callback)
      else if can_delete == "queue"
        _queue_deletion(session, params, callback)
      else
        return callback("Permission denied")

  api.trash_entity = (session, params, callback) ->
    ###
    Move the entity into or out of the trash, depending on the value of the
    boolean params.trash.
    ###
    unless utils.is_authenticated(session)
      return callback("Permission denied")
    for key in ["group", "application", "entity", "trash"]
      unless params[key]?
        return callback("Missing param #{key}")
    handler = deletion_handlers[params.application]
    return callback("Missing handler") unless handler?
    handler.can_trash session, params, (err, can_trash) ->
      return callback("Permission denied") unless can_trash
      schema.SearchIndex.findOne {
          application: params.application
          entity: params.entity
        }, (err, si) ->
          return callback(err) if err?
          return callback("Not found") unless si?
          if !!si.trash != !!params.trash
            si.trash = !!params.trash
            async.parallel [
              (done) ->
                api.post_event {
                  application: si.application
                  entity: si.entity
                  type: if params.trash then "trash" else "untrash"
                  url: si.url
                  date: new Date()
                  user: session.auth.user_id
                  group: si.sharing.group_id
                  data: {
                    entity_name: si.title
                  }
                }, (err, event) ->
                  done(err, event)

              (done) ->
                api.add_search_index si, (err, si) -> done(err, si)

              (done) ->
                handler.trash_entity(session, params, done)

            ], (err, results) ->
              return callback(err) if err?
              [event, si, handler_res] = results
              return callback(null, event, si, handler_res)
          else
            return callback(null)
      
  api.cancel_deletion = (session, deletion_request_id, callback) ->
    ###
    Cancel a pending request to delete.
    ###
    unless utils.is_authenticated(session)
      return callback("Permission denied")
    schema.DeletionRequest.findOne {_id: deletion_request_id}, (err, dr) ->
      return callback(err) if err?
      return callback("Not found") unless dr?

      handler = deletion_handlers[dr.application]
      return callback("Missing handler") unless handler?.can_delete
      handler.can_delete session, dr.entity, (err, can_delete) ->
        return callback(err) if err?
        return callback("Permission denied") unless can_delete
        query = {entity: dr.entity, application: dr.application}
        update = {trash: false}
        async.parallel [
          # Post event.
          (done) ->
            #TODO: post event
            api.post_event {
              application: dr.application
              entity: dr.entity
              type: "undeletion"
              url: dr.entity_url
              date: new Date()
              user: session.auth.user_id
              group: dr.group
              data: { entity_name: dr.title }
            }, (err, event) ->
              done(err, event)

          # Untrash
          (done) ->
            api.trash_entity {
              group: dr.group,
              entity: dr.entity,
              application: dr.application,
              trash: false
            }, done

          # Remove deletion notifications
          (done) -> schema.Notification.find({
              entity: dr.entity
              type: "deletion"
            }).remove (err) ->
              done(err)

          # Update search index.
          (done) -> schema.SearchIndex.findOneAndUpdate {
              entity: dr.entity
              application: dr.application
            }, {trash: false}, (err, si) ->
              done(err, si)

          # Remove deletion request
          (done) ->
            dr.remove (err) -> done(err)

        ], (err, results) ->
          return callback(err) if err?
          [event, untrashing, blank, si, blank] = results
          return callback(null, event, si, untrashing)

  api.confirm_deletion = (session, deletion_request_id, callback) ->
    ###
    Call to add an additional user who wishes to delete the entity referenced
    by the DeletionRequest. If the number of confirming users is above the
    threshold (hard-coded to 2 right now), the entity is deleted outright.
    ###
    unless utils.is_authenticated(session)
      return callback("Permission denied")
    schema.DeletionRequest.findOne {_id: deletion_request_id}, (err, dr) ->
      return callback(err) if err?
      return callback("Not found") unless dr?

      handler = deletion_handlers[dr.application]
      return callback("Missing handler") unless handler?.can_delete
      handler.can_delete session, dr.entity, (err, can_delete) ->
        return callback(err) if err?
        return callback("Permission denied") unless can_delete
        unless _.find(dr.confirmers, (c) -> c.toString() == session.auth.user_id)
          dr.confirmers.push(session.auth.user_id)
        #TODO: un-hardcode 2 person deletion threshold
        if dr.confirmers.length >= 2
          _delete_entity(params, callback)
        else
          dr.save (err, dr) ->
            _update_deletion_notifications(dr, callback)

  api.process_deletions = (callback) ->
    ###
    Method to call from cron to process any deletions past their waiting
    period.
    ###
    now = new Date()
    schema.DeletionRequest.find {end_date: {$lt: now}}, (err, drs) ->
      return callback(err) if err?
      async.map drs, _delete_entity, (err, results) ->
        callback(err)

  #
  # Search indices
  #

  _add_search_index_timeout = {}
  _add_search_index = (params, callback) ->
    conditions = {}
    update = {}
    for key in ["application", "entity", "type"]
      conditions[key] = params[key]
    for key in ["title", "summary", "text", "url", "trash"]
      update[key] = params[key]
    # Avoid updating sharing if not passed explicitly.
    if params.sharing?
      update.sharing = params.sharing
    # options = {upsert: true, 'new': true}
    # NOTE: findOneAndUpdate here was leading to
    # [RangeError: Maximum call stack size exceeded]
    # and 
    # Object [object Object],[object Object]  has mo method 'getRequestId'
    # under mongoose 3.5.6.
    # Couldn't figure it out; switched to a findOne + save instead.
    schema.SearchIndex.findOne conditions, (err, doc) ->
      return callback(err) if err?
      unless doc?
        doc = new schema.SearchIndex(conditions)
      for key, val of update
        doc[key] = val
      doc.save (err, doc) ->
        return callback(err) if err?
        solr.post_search_index doc, (err) ->
          callback(err, doc)

  api.add_search_index = (params, timeout, callback) ->
    if timeout and isNaN(timeout)
      callback = timeout
      timeout = null
    else
      callback or= (->)
      
    if timeout? and timeout > 0
      key = [params.application, params.entity, params.type].join(":")
      if _add_search_index_timeout[key]?
        clearTimeout(_add_search_index_timeout[key])

      _add_search_index_timeout[key] = setTimeout ->
        logger.info "Posting timeout search index: ", key
        _add_search_index(params, callback)
      , timeout
    else
      _add_search_index(params, callback)

  api.remove_search_index = (application, entity, type, callback=(->)) ->
    schema.SearchIndex.findOneAndRemove {application, entity, type}, (err, doc) ->
      return callback(err) if err?
      solr.delete_search_index {entity}, (err) ->
        return callback(err) if err?
        callback(null)

  #
  # Notifications
  #

  api.get_notifications = (email, callback) ->
    get_user email, (err, user) ->
      return callback(err) if err?
      schema.Notification.find({
        recipient: user._id
        cleared: {$ne: true}
        suppressed: {$ne: true}
        "formats.web": {$ne: null}
      }).sort('-date').limit(51).exec(callback)

  api.clear_notifications = (params, callback=(->)) ->
    query = {}
    query._id = {$in: params.notification_id.split(",")} if params.notification_id?
    query.application = params.application if params.application?
    query.entity = params.entity if params.entity?
    query.type = params.type if params.type?
    query.recipient = params.recipient if params.recipient?
    query.cleared = false
    async.series [
      (done) ->
        if params.user?
          get_user params.user, (err, doc) ->
            return done(err) if err?
            query.recipient = doc.id
            done(null, null)
        else
          done(null, null)
      (done) ->
        schema.Notification.find query, (err, docs) ->
          mark_cleared = (doc, cb) ->
            doc.cleared = true
            doc.save (err, doc) ->
              cb(err, doc)
          async.map docs, mark_cleared, done
    ], (err, results) ->
      return callback(err) if err?
      [none, notifications] = results
      callback(null, notifications)

  api.suppress_notifications = (email, notification_id, callback=(->)) ->
    get_user email, (err, user) ->
      return callback(err) if err?
      schema.Notification.findOneAndUpdate({
        recipient: user._id
        _id: notification_id
      }, {suppressed: true}, {new: true, upsert: false}, (err, doc) ->
        callback(err, doc)
      )

  api.post_notifications = (notices, callback=(->)) ->
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
          return done(null, false) unless params.sender?
          if params.sender.toString().indexOf('@') != -1
            schema.User.findOne {email: params.sender}, done
          else
            done(null, {_id: params.sender})
        (done) ->
          if params.recipient.toString().indexOf('@') != -1
            schema.User.findOne {email: params.recipient}, done
          else
            done(null, {_id: params.recipient})
      ], (err, results) ->
        return done(err) if err?
        return done("Sender '#{params.sender}' not found.") unless results[0]?
        return done("Recipient '#{params.recipient}' not found.") unless results[1]?
        # Save.
        if results[0] != false
          notice_conditions.sender = results[0]._id
        notice_conditions.recipient = results[1]._id
        schema.Notification.findOneAndUpdate(
          notice_conditions, notice_update, {'new': true, 'upsert': true}, done
        )

    async.map(notices, store_notice, callback)

  api.emit_notifications = (sockrooms, notifications, callback=(->)) ->
    async.map notifications, (notification, done) ->
      sockrooms.broadcast(notification.recipient.toString(), "notifications", {
        notifications: [notification.toJSON()]
      })
      done()
    , callback

  #
  # Profiles
  #

  api.edit_profile = (params, callback=(->)) ->
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

  api.get_events = (params, callback) ->
    # Exclude records that use the pre events-refactor-branch schema.
    filter = {entity_url: {$exists: false}}
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
      for key in ["application", "entity", "type"]
        filter[key] = params[key] if params[key]?
      schema.Event.find filter, (err, events) ->
        return callback(err) if err?
        event_json = (event.toJSON() for event in events)
        for event in event_json
          event.grammar = api.get_event_grammar(event)
        return callback(null, event_json)

  #
  # Retrieve a hierarchy of events used to create recent activity views.
  # Events returns events organized by:
  #   group -> user -> entity -> collective
  #
  api.get_event_user_hierarchy = (params, callback) ->
    async.parallel [
      (done) ->
        schema.Event.find({
          entity_url: {$exists: false}
          group: {$in: _.keys(params.groups)}
          date: {$lt: params.end, $gt: params.start}
        }).sort('group entity -date').exec (err, events) ->
          done(err, events)

      (done) ->
        schema.Notification.find({
          recipient: params.user_id
          cleared: {$ne: true}
          suppressed: {$ne: true}
          "formats.web": {$ne: null}
        }).sort('-date').limit(51).exec (err, notices) ->
          done(err, notices)
    ], (err, results) ->
      return callback(err) if err?
      [events, notices] = results
      hierarchy = {}
      for eventDoc in events
        event = eventDoc.toJSON()
        event.group = event.group?.toString()
        event.user = event.user?.toString()
        event.grammar = api.get_event_grammar(event)
        event_time = event.date.getTime()
        ident = event.user or event.data?.name or event.anon_id
        # By group
        hierarchy[event.group] ?= {
          'group': event.group
          'latest': event_time
          'users': {}
        }
        group_events = hierarchy[event.group]
        group_events.latest = event_time if event_time > group_events.latest
        # By user
        group_events.users[ident] ?= {
          'latest': event_time
          'ident': {user: event.user, name: event.data?.name, anon_id: event.anon_id}
          'entities': {}
        }
        user_events = group_events.users[ident]
        user_events.latest = event_time if event_time > user_events.latest
        # By entity
        user_events.entities[event.entity] ?= {
          'latest': event_time
          'absolute_url': event.absolute_url
          'application': event.application
          'entity_name': event.grammar[0].entity
          'collectives': {}
        }
        entity_events = user_events.entities[event.entity]
        entity_events.latest = event_time if event_time > entity_events.latest
        # By collective noun phrase
        entity_events.collectives[event.grammar[0].collective] ?= {
          'latest': event_time
          'collective': event.grammar[0].collective
          'events': []
        }
        collective = entity_events.collectives[event.grammar[0].collective]
        collective.latest = event_time if event_time > collective.latest
        collective.events.push(event)

      # Flatten objects and sort values for iteration.
      hierarchy = _.sortBy(_.values(hierarchy), (e) -> -e.latest)
      # by group
      for group in hierarchy
        user_events = group.users
        group.users = _.sortBy(_.values(group.users), (e) -> -e.latest)
        # by user
        for user in group.users
          user.entities = _.sortBy(_.values(user.entities), (e) -> -e.latest)
          # by entity (document)
          for entity in user.entities
            # Only include visits if there aren't non-visit events.
            delete entity.collectives.visits if _.size(entity.collectives) > 1
            entity.collectives = _.sortBy(_.values(entity.collectives), (e) -> -e.latest)
            for collective in entity.collectives
              # Eliminate duplicate events. They're already time-sorted by
              # mongo so we don't need to re-sort, but they aren't sorted by
              # deduplication key, so second _.uniq param must be false.
              collective.events = _.uniq collective.events, false, (e) ->
                key = [e.type, e.user, e.via_user, e.manner].concat(
                  _.sortBy(_.keys(e.data or {}))
                ).concat(
                  _.sortBy(_.values(e.data or {}))
                ).join(":")
                e.key = key
                return key
      # Populate groups and users
      for group in hierarchy
        group.group = params.groups[group.group]
        for user_events in group.users
          if user_events.ident.user
            user_events.ident.user = params.users[user_events.ident.user]
          for entity in user_events.entities
            for collective in entity.collectives
              for event in collective.events
                if event.via_user?
                  event.via_user = params.users[event.via_user]
                if event.user?
                  event.user = params.users[event.user]
      return callback(null, hierarchy, notices)

  _event_timeout_queue = {}
  _post_event = (params, callback) ->
    # Resolve user, group, via_user
    data = {}
    async.parallel [
      (done) ->
        if params.group?
          schema.Group.findOne {_id: params.group}, '_id', (err, group) ->
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
      for key in ["application", "entity", "type", "url", "date",
                  "anon_id", "data"]
        data[key] = params[key] if params[key]?
      event = new schema.Event(data)
      event.save(callback)

  api.post_event = (params, timeout, callback=(->)) ->
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

    _post_event params, (err, event) ->
      if timeout? and not err?
        _event_timeout_queue[key] = event
        setTimeout (-> delete _event_timeout_queue[key]), timeout
      return callback(err, event)

  api.get_event_grammar = (event) ->
    return grammar_getters[event.application]?.get_terms(event)

  #
  # Twinkles
  #

  api.get_twinkles = (params, callback) ->
    filter = {}
    for key in ["application", "entity", "url", "sender", "recipient"]
      filter[key] = params[key] if params[key]?
    schema.Twinkle.find(filter, callback)

  api.post_twinkle = (params, callback) ->
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

  api.delete_twinkle = (params, callback) ->
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
    
  return api
