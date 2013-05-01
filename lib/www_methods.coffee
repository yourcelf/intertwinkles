async         = require 'async'
_             = require 'underscore'
utils         = require('./utils')
thumbnails    = require './thumbnails'
logger        = require('log4js').getLogger("www")
email_invitation_view = require("../emails/invitation")

module.exports = (config) ->
  schema = require('./schema').load(config)
  solr = require("./solr_helper")(config)
  api_methods = require("./api_methods")(config)
  render_notifications = require("./email_notices").load(config).render_notifications

  _post_group_event = (session, group, type, data, callback) ->
    api_methods.post_event({
      type: type
      application: "www"
      entity: group.id
      url: "/groups/show/#{group.slug}"
      user: session.auth?.user_id
      anon_id: session.anon_id
      group: group.id
      data: data
    }, callback)


  www = {}

  #
  # Basic utilities
  #
  www.log_error = (type, req, res, err, msg) ->
    logger.error({
      type: type, error: err, message: msg, method: req.method, url: req.url
      headers: req.headers
    })
  www.handle_error = (req, res, err, msg) ->
    www.log_error("www", req, res, err, msg)
    res.statusCode = 500
    res.render("500", {
      title: "Server Error"
      initial_data: utils.get_initial_data(req?.session, config)
      conf: utils.clean_conf(config)
      flash: {}
    })

  www.ajax_handle_error = (req, res, err, msg) ->
    www.log_error("ajax", req, res, err, msg)
    res.statusCode = 500
    res.send({error: msg or "Server error", status: 500})

  www.redirect_to_login = (req, res) ->
    res.redirect("/profiles/login/?next=" + encodeURIComponent(req.url))

  www.not_found = (req, res) ->
    res.statusCode = 404
    res.render("404", {
      title: "Not Found"
      initial_data: utils.get_initial_data(req?.session, config)
      conf: utils.clean_conf(config)
      flash: {}
    })
  
  www.permission_denied = (req, res) ->
    res.statusCode = 403
    res.render("403", {
      title: "Permission denied"
      initial_data: utils.get_initial_data(req?.session, config)
      conf: utils.clean_conf(config)
      flash: {}
    })

  www.bad_request = (req, res, msg) ->
    res.statusCode = 400
    res.render("500", {
      title: "Bad Request"
      initial_data: utils.get_initial_data(req?.session, config)
      conf: utils.clean_conf(config)
      flash: {}
    })

  www.ajax_bad_request = (req, res, msg) ->
    res.statusCode = 400
    res.send({error: msg or "Bad Request", status: 400})

  #
  # Recent events for groups the given session is a member of, excluding those
  # attributed to the given session (e.g. everyone else's activity in my
  # groups).
  #
  www.get_dash_events = (session, callback) ->
    schema.Event.find({
      # Exclude records that use the pre events-refactor-branch schema.
      entity_url: {$exists: false}
      $or: [
        {group: {$in: _.keys(session.groups)}}
        {user: session.auth.user_id}
      ],
      date: {$gt: new Date() - (1000 * 60 * 60 * 24 * 14)},
    }).sort('-date').exec (err, events) ->
      return callback(err) if err?
      events_json = (event.toJSON() for event in events)
      for event in events_json
        event.grammar = api_methods.get_event_grammar(event)
      return callback(null, events_json)

  www.get_group_events = (session, group, callback) ->
    schema.Event.find({
      # Exclude records that use the pre events-refactor-branch schema.
      entity_url: {$exists: false}
      group: group._id
      date: {$gt: new Date() - (1000 * 60 * 60 * 24 * 14)}
    }).sort('-date').exec (err, events) ->
        return callback(err) if err?
        events_json = (event.toJSON() for event in events)
        for event in events_json
          event.grammar = api_methods.get_event_grammar(event)
        return callback(null, events_json)

  #
  # Basic text search for indexed documents.
  #
  www.search = (session, q, include_public, callback) ->
    params = {q}
    if not session?.auth?.user_id?
      params.public = true
    else
      params.user = session.auth.user_id
      params.public = true if include_public == true

    solr.execute_search params, params.user, (err, results) ->
      return callback(err) if err?
      for doc in results?.response?.docs
        # Absolutize urls
        doc.absolute_url = "#{config.apps[doc.application]?.url}" + doc.url
      callback(null, results)

  #
  # Edit profile
  #
  # Calls back with callback(err, user).  If `user` returns null, interpret as
  # "Permission Denied".
  www.edit_profile = (session, params, callback) ->
    schema.User.findOne {_id: session.auth.user_id}, (err, doc) ->
      return callback(err, null) if err?
      unless doc?
        return callback(null, null)
      if params.email?
        # If they've included the old email as the param, but have a current
        # email_change_request, remove the change request.
        if doc.email_change_request? and params.email == doc.email
          doc.email_change_request = null
        else if params.email != doc.email
          # Otherwise, if they have a new email, set the email_change_request
          doc.email_change_request = params.email
      doc.name = params.name if params.name?
      doc.icon.pk = params.icon if params.icon?
      doc.icon.color = params.color if params.color?
      if params.mobile_number?
        doc.mobile.number = params.mobile_number or null
      if params.mobile_carrier?
        doc.mobile.carrier = params.mobile_carrier or null
      for key in ["invitation", "activity_summaries", "group_members_changed", "needs_my_response"]
        doc.notifications[key].email = !!params["notifications_#{key}_email"]
        doc.notifications[key].sms = (
          (!!params["notifications_#{key}_sms"]) and doc.mobile.number and doc.mobile.carrier
        )
      doc.save(callback)

  #
  # Create a new group
  #
  www.create_group = (session, group_params, callback) ->
    group = _new_group_with_session(session)
    user_map = {}
    user_map[session.auth.user_id] = session.users[session.auth.user_id]
    _update_group(session,
      group,
      user_map,
      group_params,
      (err, event_data, group, clear_notices, new_notices) ->
        return callback(err) if err?
        _post_group_event(
          session,
          group,
          "create",
          event_data,
          (err, event) ->
            callback(err, group, event,
              [].concat(clear_notices or [], new_notices or []))
        )
    )

  # Create a new group with the given session's user as a method.
  _new_group_with_session = (session, callback) ->
    user = _.find(session.users, (u) -> u.email == session.auth.email)
    group = new schema.Group()
    group.members = [{
      user: session.auth.user_id
      joined: new Date()
      invited_by: null
      invited_on: null
      voting: true
    }]
    callback?(null, group)
    return group

  #
  # Update settings for a group.
  #

  # NOTE: expects the group's "members.user" and "invited_members.user" to be
  # populated, as with:
  www.update_group = (session, group, group_params, callback) ->
    user_ids = (m.user for m in group.members).concat(
                m.user for m in group.invited_members).concat(
                m.user for m in group.past_members)
    schema.User.find {_id: {$in: user_ids}}, (err, docs) ->
      return callback(err) if err?
      user_map = {}
      for user in docs
        user_map[user.id] = user
      _update_group(session,
        group,
        user_map,
        group_params,
        (err, event_data, group, clear_notices, new_notices) ->
          return callback(err) if err?
          _post_group_event(
            session,
            group,
            "update",
            event_data,
            (err, event) ->
              callback(err, group, event,
                [].concat(clear_notices or [], new_notices or []))
          )
      )

  # Create an invitation object; creating the user if needed.  Calls back with:
  # callback(err, invitation)
  _create_invitation = (session, email, params, callback) ->
    return callback() unless params?
    invitation = {
      invited_by: session.auth.user_id
      invited_on: new Date()
      role: params.role
      voting: params.voting
    }
    schema.User.findOne {email: email}, (err, doc) ->
      return callback(err) if err?
      if doc?
        invitation.user = doc._id
        return callback(null, invitation)
      else
        doc = new schema.User({name: "", email: email, joined: null})
        doc.save (err, doc) ->
          return callback(err) if err?
          invitation.user = doc._id
          return callback(null, invitation)

  # Process a member changeset, adding and removing group members and invitees.
  # Calls back with:
  #     callback(err,
  #              clear_group_notices,   -- array of ID's of removed users
  #              add_invitation_notices -- array of ID's of invited users
  #              )
  # Does not save the changes made to the group; but does create User models.
  _process_member_changeset = (session, group, user_map, member_changeset, callback) ->
    return callback(null, [], []) unless member_changeset?
    # List of IDs of users we're removing, and need to clear all their
    # group-related notices.
    clear_group_notices     = []
    # List of IDs of users we're inviting, and need to give invitations
    # once the group saves successfully.
    add_invitation_notices  = []
    # Update properties of existing members/invitees.
    for email, updates of member_changeset.update
      continue unless updates? and updates != {}
      # Look for the user among invited members.
      membership = _.find group.invited_members or [], (m) ->
        user_map[m.user].email == email
      # Look for the user among current members.
      if not membership?
        membership = _.find group.members, (m) ->
          user_map[m.user].email == email
      if membership?
        if updates.role?
          membership.role = updates.role
        if updates.voting?
          membership.voting = updates.voting
   
    # Remove members
    for email, removed of member_changeset.remove
      continue if not removed
      found = false
      
      # Look in invitations. Do it as a straight loop, so we can get an
      # index, splice, and add to notice clearing list
      for invitation, i in group.invited_members
        if user_map[invitation.user].email == email
          member = group.invited_members.splice(i, 1)[0]
          found = true
          clear_group_notices.push(invitation.user)
          break

      continue if found

      # Look in memberships. Do it as a straight loop, so we can get an
      # index, and splice, and re-insert in past_members.
      for membership, i in group.members
        if user_map[membership.user].email == email
          group.members.splice(i, 1)
          removal = {}
          for key in ["invited_by", "invited_on", "role", "voting", "user", "joined"]
            removal[key] = membership[key]
          removal.left = new Date()
          removal.removed_by = session.auth.user_id
          group.past_members.push(removal)
          clear_group_notices.push(membership.user)
          break

    # Addition of new invitees.
    # Flatten {"email@example.com": {role: "President", voting: true}}
    # into  [["email@example.com, {role: "President, voting: true}]]
    # to send to async.map
    flat_invitees = ([k, v] for k,v of member_changeset.add or {})
    async.map(flat_invitees, (details, done) ->
      # Create invitation and add to the group.
      [email, params] = details
      return done() unless params?
      _create_invitation session, email, params, (err, invitation) ->
        return done(err) if err?
        add_invitation_notices.push(invitation.user)
        group.invited_members.push(invitation)
        done()
    , (err, done) ->
      return callback(err) if err?
      callback(null, clear_group_notices, add_invitation_notices)
    )

  # Add group logo.
  _add_group_logo = (session, group, file_path, callback) ->
    return callback() unless file_path?
    thumbnails.upload file_path, "/group_logos", (err, paths) ->
      return callback(err) if err?
      group.logo = paths
      return callback(null, paths)

  # Remove group logo
  _remove_group_logo = (group, callback) ->
    return callback() unless group.logo?.full?
    thumbnails.remove [group.logo.full, group.logo.thumb], "/group_logos", (err) ->
      callback(err)

  # Main routine for processing group updates.
  _update_group = (session, group, user_map, group_update, callback) ->
    # Collector for event data we will create as a result of this update.
    event_data = {}
    # Ids of users needing notices of various kinds.
    notice_ids = {}
    async.parallel [
      # Update plain group properties.
      (done) ->
        if group_update.name and group.name != group_update.name
          event_data.old_name = group.name if group.name?
          group.name = group_update.name
          event_data.name = group_update.name
          # The URL slug. XXX: Should we allow this to change? Breaks URLs...
          group.slug = utils.slugify(group.name)
        done()
      
      # Changes in group membership and invitees.
      (done) ->
        if not group_update.member_changeset
          return done()
        _process_member_changeset(session, group, user_map, group_update.member_changeset
        , (err, clear_group_notices, add_invitation_notices) ->
            notice_ids.clear_group = clear_group_notices
            notice_ids.invitation = add_invitation_notices
            # Flatten the member changeset data so that we don't end up with
            # invalid mongo keys.
            event_data.member_changeset = {}
            for key in ["add", "update", "remove"]
              if not group_update.member_changeset[key]
                continue
              event_data.member_changeset[key] = (
                [k, v] for k,v of group_update.member_changeset[key]
              )
            done(err)
        )

      # File uploads and file removals
      (done) ->
        if group_update.logo_file?
          _remove_group_logo group, (err) ->
            return done(err) if err?
            _add_group_logo(session, group, group_update.logo_file.path
            , (err, paths) ->
              return done(err) if err?
              event_data.logo = paths
              done()
            )
        else if group_update.remove_logo
          event_data.remove_logo = true
          _remove_group_logo(group, done)
        else
          done()

    ], (err) ->
      return callback(err) if err?
      # Unpopulate user fields
      for g in [group.members, group.invited_members, group.past_members]
        for m in g
          m.user = m.user._id if m.user._id?
      group.save (err, group) ->
        return callback(err) if err?

        # Process notifications
        async.parallel [
          (done) ->
            return done() unless notice_ids.clear_group?.length
            api_methods.clear_notifications({
              recipient: {$in: notice_ids.clear_group}
            }, done)

          (done) ->
            return done() unless notice_ids.invitation?.length
            # Render notifications for each recipient.
            formats = {}
            get_user = (id, cb) ->
              user = user_map[id.toString()]
              if user then cb(null, user) else schema.User.findOne {_id: id}, cb
            get_user session.auth.user_id, (err, sender) ->
              return done(err) if err?
              async.map notice_ids.invitation, (recipient_id, done) ->
                get_user recipient_id, (err, recipient) ->
                  return done(err) if err?
                  render_notifications email_invitation_view, {
                    group: group
                    sender: sender
                    recipient: recipient
                    url: config.api_url + "/groups/join/#{group.slug}"
                    application: "www"
                  }, (err, rendered) ->
                    formats[recipient_id.toString()] = rendered
                    done()
              , (err) ->
                # All rendered.  Now generate the notifications.
                notice_params = ({
                  application: "www"
                  type: "invitation"
                  entity: group.id
                  recipient: id
                  url: "/groups/join/#{group.slug}"
                  sender: session.auth.user_id
                  formats: format
                } for id, format of formats)
                api_methods.post_notifications(notice_params, done)

          (done) ->
            # Refresh our session's definition of groups and users. This will
            # happen again anyway a few seconds after the next page load once
            # persona gets around to returning, but when we've just updated the
            # group, it's important to see the result immediately.
            api_methods.get_groups(session.auth.email, (err, res) ->
              return done(err) if err?
              session.groups = res.groups
              session.users = res.users
              done(null, null)
            )
        ], (err, results) ->
          return callback(err) if err?
          [clear_notices, new_notices, none] = results
          event_data.entity_name = group.name
          return callback(null, event_data, group, clear_notices, new_notices)

  #
  # Verify that the user with the given session has been invited to the group
  # identified by the given slug.  Callback with:
  #       callback(err, group)
  # where `group` is the properly invited group if any, or null if the user isn't invited.
  www.verify_invitation = (session, group_slug, callback) ->
    schema.Group.findOne {slug: group_slug}, (err, group) ->
      return callback(err, group) if err? or not group?
      invitation = _.find group.invited_members, (m) ->
        m.user.toString() == session.auth?.user_id
      callback(null, group, invitation)

  www.process_invitation = (session, group, accepted, callback) ->
    invitation = null
    for i in [0...group.invited_members.length]
      if group.invited_members[i].user.toString() == session.auth.user_id
        invitation = group.invited_members.splice(i, 1)[0].toObject()
        break
    return callback("Invitation not found") unless invitation?

    if accepted
      # Convert the invitation instance to a membership instance.
      delete invitation._id
      delete invitation.email
      invitation.user = session.auth.user_id
      invitation.joined = new Date()
      group.members.push(invitation)

    # Save the modified group with invitation removed, and membership maybe
    # added.
    group.save (err, group) ->
      return callback(err) if err?
      async.parallel [
        (done) ->
          _post_group_event(
            session,
            group,
            if accepted then "join" else "decline",
            {entity_name: group.name, user: session.users[invitation.user]?.email},
            done)

        (done) ->
          api_methods.clear_notifications {
            user: session.auth.user_id
            entity: group.id
            type: "invitation"
          }, (err, notices) ->
            done(err, notices)

      ], (err, results) ->
        return callback(err) if err?
        [event, notices] = results
        return callback(null, group, event, notices)

  return www
