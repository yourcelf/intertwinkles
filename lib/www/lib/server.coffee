express       = require 'express'
socketio      = require 'socket.io'
intertwinkles = require 'node-intertwinkles'
RoomManager   = require('iorooms').RoomManager
RedisStore    = require('connect-redis')(express)
_             = require 'underscore'
async         = require 'async'
api           = require './api'
carriers      = require './carriers'
thumbnails    = require './thumbnails'
logger        = require('log4js').getLogger()

start = (config, app, io, sessionStore) ->
  schema = require('./schema').load(config)
  iorooms = new RoomManager("/io-www", io, sessionStore)

  #
  # API
  #
  api.route(config, app)

  #
  # Routes
  #
  
  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "www"},
        intertwinkles.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: intertwinkles.clean_conf(config)
      flash: req.flash(),
    }, obj)

  handle_error = (req, res, err, msg) ->
    logger.error(err)
    res.statusCode = 500
    res.send(msg or "Server error")

  redirect_to_login = (req, res) ->
    res.redirect("/profiles/login/?next=" + encodeURIComponent(req.url))

  #
  # About pages
  #

  app.get '/', (req, res) ->
    is_authenticated = intertwinkles.is_authenticated(req.session)
    async.series [
      (done) ->
        return done() unless is_authenticated
        async.parallel [
          # Your activity
          (done) ->
            schema.Event.find(
              {user: req.session.auth.user_id}
            ).sort('-date').limit(20).exec done

          # Your groups' activity
          (done) ->
            schema.Event.find({
                group: {$in: _.keys(req.session.groups)},
                user: {$ne: req.session.auth.user_id}
            }).sort('-date').limit(20).exec done

          # Your docs
          (done) ->
            intertwinkles.list_group_documents(
              schema.SearchIndex, req.session, done, {}, "-modified", 0, 20, true
            )

        ], done

    ], (err, results) ->
      return handle_error(req, res, err) if err?
      results = results[0]
      activity = null
      if is_authenticated
        if results[0].length + results[1].length + results[2].length > 0
          activity = {
            user: results[0]
            group: results[1]
            docs: results[2]
          }

      res.render 'index', context(req, {
        title: "InterTwinkles: Twinkling all over the InterWebs"
        hero_apps: ["firestarter", "twinklepad", "dotstorm", "resolve"]
        activity: activity
        groups: req.session.groups
      })

  app.get '/about/', (req, res) ->
    res.render 'about/index', context(req, {
      title: "About InterTwinkles"
    })
  app.get '/about', (req, res) -> res.redirect("/about/")

  app.get '/about/terms/', (req, res) ->
    res.render 'about/terms', context(req, {
      title: "Terms of Use"
    })
  app.get '/about/terms', (req, res) -> res.redirect("/about/terms/")

  app.get '/about/privacy/', (req, res) ->
    res.render 'about/privacy', context(req, {
      title: "Privacy Policy"
    })
  app.get '/about/privacy', (req, res) -> res.redirect("/about/privacy/")

  app.get '/about/related/', (req, res) ->
    res.render 'about/related', context(req, {
      title: "Related Work"
    })
  app.get '/about/related', (req, res) -> res.redirect("/about/related/")

  app.get '/test/', (req, res) ->
    res.render 'test', context(req, { title: "Test" })

  #
  # Search
  #

  app.get '/search/', (req, res) ->
    params = {}
    async.waterfall [
      (done) ->
        if req.query.q
          params.q = req.query.q
          params.public = true unless req.query.public == 'false'
          if intertwinkles.is_authenticated(req.session)
            params.user = req.session.auth.user_id
          intertwinkles.search params, config, (err, results) ->
            done(err, results)
        else
          done(null, null)
    ], (err, results) ->
      # Absolutize urls
      docs = results?.response.docs or []
      for doc in docs
        doc.url = "#{config.apps[doc.application].url}" + doc.url
      res.render 'search', context(req, {
        authenticated: intertwinkles.is_authenticated(req.session)
        title: "Search",
        docs: docs
        highlighting: results?.highlighting
        q: req.query.q
      })
  app.get "/search", (req, res) -> res.redirect("/search/")

  #
  # Edit profile settings
  #

  app.get '/profiles/edit/', (req, res) ->
    if not intertwinkles.is_authenticated(req.session)
      return redirect_to_login(req, res)

    schema.User.findOne {email: req.session.auth.email}, (err, doc) ->
      return handle_error(req, res, err) if err?
      unless doc?
        return res.send("Permission denied", 403)

      # We don't use 'toObject' or 'toJSON' here, because those methods remove
      # private fields like mobile numbers that we want to display to the
      # owning user.
      user = {
        _id: doc.id
        name: doc.name
        joined: doc.joined
        email: doc.email
        email_change_requst: doc.email_change_request
        mobile: { number: doc.mobile.number, carrier: doc.mobile.carrier }
        icon: {
          pk: doc.icon.pk, name: doc.icon.name, color: doc.icon.color,
          tiny: doc.icon.tiny, small: doc.icon.small,
          medium: doc.icon.medium, large: doc.icon.large
        }
      }
      res.render 'profiles/edit', context(req, {
        title: "Profile settings"
        user: user
        carrier_list: _.keys(carriers)
      })
  app.get "/profiles/edit", (req, res) -> res.redirect("/profiles/edit/")

  app.post '/profiles/edit/', (req, res) ->
    if not intertwinkles.is_authenticated(req.session)
      return res.send("Permission denied", 403)

    schema.User.findOne {email: req.session.auth.email}, (err, doc) ->
      return handle_error(req, res, err) if err?
      unless doc?
        return res.send("Permission denied", 403)

      doc.set("name", req.body.name) if req.body.name
      doc.set("email", req.body.email) if req.body.email
      doc.set("icon.pk", req.body.icon) if req.body.icon
      doc.set("icon.color", req.body.color) if req.body.color
      doc.set("mobile.number", req.body.mobile_number) if req.body.mobile_number
      doc.set("mobile.carrier", req.body.mobile_carrier) if req.body.mobile_carrier
      
      doc.save (err, doc) ->
        if err?
          # TODO: Show a pretty 500 error page
          res.statusCode = 400
          res.send("Error!")
          logger.error(req.body)
          logger.error(err)
        else
          req.session.users[doc.id] = doc.toObject()
          res.redirect(req.query.next or "/")
  app.post '/profiles/edit', (req, res) -> res.redirect("/profiles/edit/")

  app.get '/profiles/icon_attribution/', (req, res) ->
    res.render 'profiles/icon_attribution', context(req, {
      title: "Icon Attribution"
    })
  app.get '/profiles/icon_attribution', (req, res) ->
    res.redirect("/profiles/icon_attribution/")

  app.get '/profiles/login/', (req, res) ->
    if intertwinkles.is_authenticated(req.session)
      return res.redirect(req.query.next or "/")
    res.render 'profiles/login', context(req, {
      title: "Sign in"
      next: req.query.next
    })
  app.get '/profiles/login', (req, res) -> res.redirect("/profiles/login/")

  app.get '/profiles/logout/', (req, res) ->
    intertwinkles.clear_auth_session(req.session)
    res.render 'profiles/logout', context(req, {
      title: "Logging out..."
    })
  app.get '/profiles/logout', (req, res) -> res.redirect("/profiles/logout/")

  #
  # Edit group settings.
  #
  update_group = (req, res, group, callback) ->
    event_data = {}
    # Name of the group
    if req.body.name? and req.body.name != group.name
      group.name = req.body.name
      event_data.name = req.body.name
      # The URL slug. XXX: Should we allow this to change? Breaks URLs....
      group.slug = intertwinkles.slugify(req.body.name)
    
    # List of IDs of users we're removing, and need to clear all their
    # group-related notices
    clear_group_notices     = []
    # List of IDs of users we're inviting, and need to give invitations
    # once the group saves successfully.
    add_invitation_notices  = []
    
    try
      member_changeset = JSON.parse(req.body.member_changeset or "{}")
    catch e
      return handle_error(req, res, "Broken JSON for member changeset")
    if member_changeset != {}
      event_data.members = JSON.stringify(member_changeset)
    async.parallel [
      (done) ->
        # Update properties of members
        for email, updates of member_changeset.update
          continue unless updates? and updates != {}
          # Look in invited members first.
          membership = _.find group.invited_members or [], (m) -> m.email == email
          # If it isn't found, look in current members.
          if not membership?
            membership = _.find group.members, (m) -> m.user.email == email
          if membership?
            if updates.role?
              membership.role = updates.role
            if updates.voting?
              membership.voting = updates.voting
        # Remove members
        for email, removed of member_changeset.remove
          continue if not removed
          found = false
          # Look in invitations.
          for invitation, i in group.invited_members
            if invitation.user.email == email
              member = group.invited_members.splice(i, 1)[0]
              found = true
              clear_group_notices.push(invitation.user.id)
          if not found
            # Look in memberships.
            for membership, i in group.members
              if membership.user.email == email
                group.members.splice(i, 1)
                #membership.user = membership.user._id # Un-populate user
                membership.left = new Date()
                membership.removed_by = req.session.auth.user_id
                group.past_members.push(membership)
                clear_group_notices.push(membership.user.id)
                break
        done()
      (done) ->
        # Addition of new invitees.
        flat_invitees = ([k, v] for k,v of member_changeset.add)
        add_user = (details, done) ->
          [email, invitation] = details
          return done() unless invitation?
          invitation = {
            invited_by: req.session.auth.user_id
            invited_on: new Date()
            role: invitation.role
            voting: invitation.voting
          }
          schema.User.findOne {email: email}, (err, doc) ->
            return handle_error(req, res, err) if err?
            if doc?
              invitation.user = doc.id
              add_invitation_notices.push(doc.id)
              group.invited_members.push(invitation)
              done()
            else
              # User not found; create a new user account.
              doc = new schema.User({name: "", email: email, joined: null})
              doc.save (err, doc) ->
                return handle_error(req, res, err) if err?
                invitation.user = doc.id
                group.invited_members.push(invitation)
                add_invitation_notices.push(doc.id)
                done()
        async.map(flat_invitees, add_user, done)

      (done) ->
        # File uploads and file removals.
        if req.files.logo.size > 0
          if req.files.logo.type.substring(0, 'image/'.length) == 'image/'
            async.series([
              (done) ->
                # Clear old thumbnail, if any.
                return done() unless group.logo?.full?
                thumbnails.remove [group.logo.full, group.logo.thumb], "/group_logos", (err) ->
                  return handle_error(req, res, err) if err?
                  done()
              (done) ->
                thumbnails.upload req.files.logo.path, "/group_logos", (err, paths) ->
                  return handle_error(req, res, err) if err?
                  group.logo = paths
                  event_data.logo = paths
                  done()
            ], done)
        else if req.body.remove_logo
          thumbnails.remove [group.logo.full, group.logo.thumb], "/group_logos", (err) ->
            return handle_error(req, res, err) if err?
            group.logo.full = null
            group.logo.thumb = null
            event_data.remove_logo = true
            done()
        else
          done()
    ], (err, results) ->
      # Unpopulate user fields.
      for m in group.members
        m.user = m.user._id if m.user._id?
      for m in group.invited_members
        m.user = m.user._id if m.user._id?
      for m in group.past_members
        m.user = m.user._id if m.user._id?

      # All done. save the group.
      group.save (err, group) ->
        return handle_error(req, res, err) if err?
        async.parallel [
          (done) ->
            return done() unless clear_group_notices.length > 0
            # Clear group-related notices from anyone who was removed from the
            # group.
            intertwinkles.clear_notices({
              recipient: {$in: clear_group_notices}
              group: group.id
            }, config, done)
          (done) ->
            # Add invitation notices for any new invitees.
            return done() unless add_invitation_notices.length > 0
            notice_params = ({
              application: "www"
              type: "invitation"
              entity: group.id
              group: group.id
              recipient: id
              url: "/groups/join/#{group.slug}"
              sender: req.session.auth.user_id
              formats: {
                web: """
                  You've been invited to join #{group.name}! Please accept
                  or refuse the invitation.
                """
              }
            } for id in add_invitation_notices)
            intertwinkles.post_notices(notice_params, config, done)
          (done) ->
            # Refresh our session's definition of groups and users. This will
            # happen again anyway a few seconds after the next page load once
            # persona gets around to returning, but when we've just updated the
            # group, it's important to see the result immediately.
            intertwinkles.get_groups(req.session.auth.email, config, (err, groups) ->
              return done(err) if err?
              req.session.groups = groups
              done()
            )
        ], (err, results) ->
          return handle_error(req, res, err) if err?
          callback(group, event_data)

  app.get '/groups/new/', (req, res) ->
    unless intertwinkles.is_authenticated(req.session)
      return redirect_to_login(req, res)

    res.render 'groups/edit', context(req, {
      title: "New group"
      group: {}
    })
  app.get '/groups/new', (req, res) -> res.redirect('/groups/new/')

  app.post '/groups/new/', (req, res) ->
    unless intertwinkles.is_authenticated(req.session)
      return redirect_to_login(req, res)

    user = _.find(req.session.users, (u) -> u.email == req.session.auth.email)

    group = new schema.Group()
    group.members = [{
      user: user._id
      joined: new Date()
      invited_by: null
      invited_on: null
      voting: true
    }]
    update_group req, res, group, (group, event_data) ->
      intertwinkles.post_event {
        type: "create"
        application: "www"
        entity: group.id
        entity_url: "/groups/#{group.slug}"
        user: req.session.auth.email
        group: group.id
        data: {
          title: "group #{group.name}"
          action: event_data
        }
      }, config
      return res.redirect("/groups/edit/#{group.slug}")
  app.post '/groups/new', (req, res) -> res.redirect("/groups/new/")

  app.get '/groups/is_available/', (req, res) ->
    unless intertwinkles.is_authenticated(req.session)
      return res.send {error: 'Permission denied'}, 403
    unless req.query.slug?
      return res.send {error: "Missing required 'slug' param", status: 400}, 400
    schema.Group.findOne {slug: intertwinkles.slugify(req.query.slug)}, "_id", (err, doc) ->
      return handle_error(req, res, {error: 'Server error'}) if err?
      res.send({available: (not doc?) or doc.id == req.query._id})

  app.get '/groups/edit/:slug/', (req, res) ->
    unless intertwinkles.is_authenticated(req.session)
      return redirect_to_login(req, res)

    schema.Group.findOne({slug: req.params.slug}).populate('members.user').exec (err, doc) ->
      return handle_error(req, res) if err?
      unless doc?
        return res.send("Not found", 404)

      membership = _.find doc.members, (m) -> m.user.email == req.session.auth.email
      unless membership?
        return res.send("Permission denied", 403)
      res.render 'groups/edit', context(req, {
        title: "Edit " + doc.name
        group: doc
      })
  app.get "/groups/edit/:slug", (req, res) -> res.redirect("/groups/edit/#{req.params.slug}/")

  app.post '/groups/edit/:slug/', (req, res) ->
    unless intertwinkles.is_authenticated(req.session)
      return res.send("Permission denied", 403)

    schema.Group.findOne({slug: req.params.slug}).populate(
      'members.user'
    ).populate('invited_members.user').exec (err, doc) ->
      return handle_error(req, res) if err?
      unless doc?
        return res.send("Not found", 404)

      # Ensure that we are a member of this group.
      membership = _.find doc.members, (m) -> m.user.email == req.session.auth.email
      unless membership?
        return res.send("Permission denied", 403)

      user = _.find(req.session.users, (u) -> u.email == req.session.auth.email)
      update_group req, res, doc, (group, event_data) ->
        intertwinkles.post_event {
          type: "update"
          application: "www"
          entity: group.id
          entity_url: "/groups/#{group.slug}"
          user: req.session.auth.email
          group: group.id
          data: {
            title: "group #{group.name}"
            action: event_data
          }
        }, config
        return res.redirect("/groups/edit/#{group.slug}")

  verify_invitation = (req, res, next) ->
    unless intertwinkles.is_authenticated(req.session)
      return redirect_to_login(req, res)
    schema.Group.findOne {slug: req.params.slug}, (err, group) ->
      unless group?
        return res.send("Not found", 404)
      invitation = _.find group.invited_members, (m) ->
        m.user.toString() == req.session.auth.user_id
      if not invitation?
        return res.send("Permission denied", 403) #TODO: friendlier error
      next(group)
  app.post '/groups/edit/:slug', (req, res) -> req.redirect("/groups/edit/#{req.params.slug}")

  app.get '/groups/join/:slug/', (req, res) ->
    verify_invitation req, res, (group) ->
      return res.render 'groups/join', context(req, {
        title: "Join " + group.name
        group: group
      })
  app.get '/groups/join/:slug', (req, res) -> res.redirect("/groups/join/#{req.params.slug}/")

  app.post '/groups/join/:slug/', (req, res) ->
    verify_invitation req, res, (group) ->
      for i in [0..group.invited_members.length]
        if group.invited_members[i].user.toString() == req.session.auth.user_id
          invitation = group.invited_members.splice(i, 1)[0].toObject()
          if req.body.accept
            delete invitation._id
            delete invitation.email
            invitation.user = req.session.auth.user_id
            invitation.joined = new Date()
            group.members.push(invitation)
          group.save (err, group) ->
            return handle_error(req, res, err) if err?
            event = {
              application: "www"
              entity: group._id
              entity_url: "/groups/#{group.slug}"
              user: req.session.auth.email
              group: group._id
              data: {
                title: group.name
                action: invitation
              }
            }
            if req.body.accept
              req.flash('success', "Welcome to #{group.name}!")
              event.type = "join"
            else
              req.flash("success", "Invitation successfully declined.")
              event.type = "decline"
            intertwinkles.post_event event, config

            intertwinkles.clear_notices {
              recipient: req.session.auth.user_id
              group: group.id
              type: "invitation"
            }, config, (err, result) ->
              return handle_error(req, res, err) if err?
              return res.redirect("/")
          break
  app.post '/groups/join/:slug', (req, res) -> res.redirect("/groups/join/#{req.params.slug}/")

  app.get '/groups/show/:slug/', (req, res) ->
    return redirect_to_login(req, res) unless intertwinkles.is_authenticated(req.session)
    schema.Group.findOne {slug: req.params.slug}, (err, doc) ->
      return handle_error(req, res, err) if err?
      return res.send("Not found", 404) if not doc?
      unless _.find(doc.members, (m) -> m.user.toString() == req.session.auth.user_id)
        return res.send("Permission denied", 403)

      async.parallel [
        (done) ->
          schema.SearchIndex.find({
            'sharing.group_id': doc._id
          }).sort('-modified').exec done

      ], (err, results) ->
        [search_indexes] = results
        res.render "groups/show", context(req, {
          title: doc.name
          group: doc
          docs: search_indexes
        })
  app.get '/groups/show/:slug', (req, res) -> res.redirect("/groups/join/#{req.params.slug}/")

  return {app}

module.exports = {start}
