utils         = require './utils'
_             = require 'underscore'
async         = require 'async'
carriers      = require './carriers'
thumbnails    = require './thumbnails'
multiparty    = require 'multiparty'
logger        = require('log4js').getLogger()

route = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  api_methods = require("./api_methods")(config)
  www_methods = require("./www_methods")(config)
  solr = require("./solr_helper")(config)
  email_notices = require("./email_notices").load(config)

  #
  # Routes
  #

  context = (req, jade_context, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "www"},
        utils.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: utils.clean_conf(config)
      flash: req.flash(),
    }, jade_context)

  #
  # About pages
  #

  app.get '/', (req, res) ->
    # Show the landing page if we're not signed in.
    if (not utils.is_authenticated(req.session))
      return res.render 'home/landing', context(req, {
        title: "InterTwinkles: Twinkling all over the InterWebs"
      })
    group_ids = _.keys(req.session.groups)
    if group_ids.length == 0
      return res.redirect("/about/starting/")

    # Show the dashboard if we are signed in.
    async.parallel [
      (done) ->
        www_methods.get_dash_events(req.session, done)
      (done) ->
        # N queries for N groups. Most users should have only a tiny number, so
        # this is OK for now, but potentially problematic some day.
        async.map group_ids, (group_id, done) ->
          finish = (err, docs) -> done(err, {group_id: group_id, docs: docs})
          utils.list_group_documents(schema.SearchIndex, req.session, finish,
            {"sharing.group_id": group_id, trash: {$ne: true}}, "-modified", 0, 10, true
          )
        , done
    ], (err, results) ->
      return www_methods.handle_error(req, res, err) if err?
      [events, groups_docs] = results
      res.render 'home/dashboard', context(req, {
        title: "InterTwinkles"
      }, {
        active_name: "Home",
        events: events,
        groups_docs: groups_docs
      })

  utils.append_slash(app, '/dashboard')
  app.get '/dashboard/', (req, res) ->
    if utils.is_authenticated(req.session)
      return res.redirect("/")
    else
      return res.redirect("/profiles/login?next=%2f")

  utils.append_slash(app, '/trash')
  app.get '/trash/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.redirect_to_login(req, res)

    async.parallel [
      (done) ->
        utils.list_group_documents(schema.SearchIndex, req.session, done,
          {trash: true}, "-modified", 0, null, true
        )
      (done) ->
        schema.DeletionRequest.find {
          group: {$in: _.keys(req.session.groups)}
        }, (err, docs) ->
          done(err, docs)

    ], (err, results) ->
      return www_methods.handle_error(req, res, err) if err?
      [docs, deletion_requests] = results
      return res.render "home/trash", context(req, {
        title: "Trash"
      }, {
        active_name: "Home"
        trash_docs: docs
        deletion_requests: deletion_requests
      })

  utils.append_slash(app, '/deletionrequest/[^/]+')
  app.get '/deletionrequest/:id/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.redirect_to_login(req, res)
    schema.DeletionRequest.findOne {
      _id: req.params.id
    }, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      # Must be group member in order to manage deletion requests.
      unless _.find(_.keys(req.session.groups), (g) -> g == doc.group.toString())
        return www_methods.permission_denied(req, res)
      api_methods.get_events {entity: doc.entity}, (err, events) ->
        return www_methods.handle_error(req, res, err) if err?
        return res.render "home/deletionrequest", context(req, {
          title: "Deletion Request"
          deletion_request: doc
          can_confirm: not _.find(doc.confirmers,
            ((c) -> c.toString() == req.session.auth.user_id))
        }, {
          deletion_request: doc
          entity_events: events
        })

  app.post '/deletionrequest/:id/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.redirect_to_login(req, res)
    schema.DeletionRequest.findOne {
      _id: req.params.id
    }, (err, dr) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless dr?
      # Must be group member in order to manage deletion requests.
      unless _.find(_.keys(req.session.groups), (g) -> g == dr.group.toString())
        return www_methods.permission_denied(req, res)

      if req.body.delete
        api_methods.confirm_deletion req.session, dr._id, (err, update) ->
          return www_methods.handle_error(req, res, err) if err?
          if update?
            req.flash("info", "You have voted to delete.")
          else
            req.flash("success", "Item deleted.")
          res.redirect("/")
      else
        api_methods.cancel_deletion req.session, dr.id, (err) ->
          return www_methods.handle_error(req, res, err) if err?
          req.flash("success", "Deletion cancelled.")
          res.redirect("/")

  utils.append_slash(app, "/feedback")
  app.get '/feedback/', (req, res) ->
    res.render 'home/feedback', context(req, {
      title: "Feedback &amp; Support"
    }, {active_name: "Feedback"})

  utils.append_slash(app, "/about")
  app.get '/about/', (req, res) ->
    res.render 'home/about/index', context(req, {
      title: "About InterTwinkles"
    }, {active_name: "About"})

  utils.append_slash(app, "/about/starting")
  app.get '/about/starting/', (req, res) ->
    res.render 'home/starting', context(req, {
      title: "Getting Started with InterTwinkles"
    }, {active_name: "Getting Started"})

  utils.append_slash(app, "/about/more")
  app.get '/about/more/', (req, res) ->
    res.render 'home/more', context(req, {
      title: "More InterTwinkles"
    }, {active_name: "More"})


  utils.append_slash(app, "/about/terms")
  app.get '/about/terms/', (req, res) ->
    res.render 'home/about/terms', context(req, {
      title: "Terms of Use"
    }, {active_name: "Terms"})

  utils.append_slash(app, "/about/dmca")
  app.get '/about/dmca/', (req, res) ->
    res.render 'home/about/dmca', context(req, {
      title: "DMCA"
    }, {active_name: "DMCA"})

  utils.append_slash(app, "/about/privacy")
  app.get '/about/privacy/', (req, res) ->
    res.render 'home/about/privacy', context(req, {
      title: "Privacy Policy"
    }, {active_name: "Privacy"})

  utils.append_slash(app, "/about/related")
  app.get '/about/related/', (req, res) ->
    res.render 'home/about/related', context(req, {
      title: "Related Work"
    }, {active_name: "Related"})

  utils.append_slash(app, "/about/changelog")
  app.get '/about/changelog/', (req, res) ->
    res.render 'home/about/changelog', context(req, {
      title: "Change log"
    }, {active_name: "Changes"})

  utils.append_slash(app, "/about/stats")
  app.get '/about/stats/', (req, res) ->
    if not utils.is_authenticated(req.session)
      return www_methods.redirect_to_login(req, res)
    async.parallel [
      (done) -> schema.User.count (err, len) -> done(err, len)
      (done) -> schema.Group.count (err, len) -> done(err, len)
      (done) -> schema.SearchIndex.count (err, len) -> done(err, len)
      (done) -> schema.Event.count (err, len) -> done(err, len)
    ], (err, results) ->
      return www_methods.handle_error(req, res, err) if err?
      [total_users, total_groups, total_documents, total_events] = results
      online_now = _.size(sockrooms.sessionIdToSockets)
      title = "Stats"
      res.render 'home/about/stats', context(req, {
        title, total_users, total_groups, total_documents, total_events, online_now
      }, {active_name: "Stats"})

  #
  # Search
  #

  utils.append_slash(app, "/search")
  app.get '/search/', (req, res) ->
    respond = (err, results) ->
      return www_methods.handle_error(req, res, err) if err?
      res.render 'home/search', context(req, {
        authenticated: utils.is_authenticated(req.session)
        title: "Search",
        docs: results?.response?.docs or []
        highlighting: results?.highlighting or {}
        q: req.query.q
      }, {active_name: "Search"})

    return respond(null, {}) unless req.query.q

    www_methods.search(
      req.session, req.query.q, not req.query.public == 'false', respond
    )


  #
  # Edit profile settings
  #

  utils.append_slash(app, "/profiles/edit", ["get", "post"])
  app.get '/profiles/edit/', (req, res) ->
    if not utils.is_authenticated(req.session)
      req.flash("info", "You must sign in to edit your profile.")
      return www_methods.redirect_to_login(req, res)

    schema.User.findOne {email: req.session.auth.email}, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      unless doc?
        return www_methods.permission_denied(req, res)

      # We don't use 'toObject' or 'toJSON' here, because those methods remove
      # private fields like mobile numbers that we want to display to the
      # owning user.  This safe default is nice to avoid having to clean things
      # all over the place, but it means we need to manually deconstruct this
      # when we want those private fields.  Which is only here.
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
        notifications: {
          invitation: {
            email: doc.notifications.invitation.email
            sms: doc.notifications.invitation.sms
          }
          needs_my_response: {
            email: doc.notifications.needs_my_response.email
            sms: doc.notifications.needs_my_response.sms
          }
          activity_summaries: {
            email: doc.notifications.activity_summaries.email
            sms: doc.notifications.activity_summaries.sms
          }
          group_members_changed: {
            email: doc.notifications.group_members_changed.email
            sms: doc.notifications.group_members_changed.sms
          }
        }
      }
      res.render 'home/profiles/edit', context(req, {
        title: "Profile settings"
        user: user
        carrier_list: _.keys(carriers)
      }, {active_name: "Profile"})

  app.post '/profiles/edit/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.permission_denied(req, res)
    www_methods.edit_profile req.session, req.body, (err, user) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.permission_denied(req, res) unless user?
      req.flash("success", "Settings updated.")
      req.session.users[user.id] = user
      return res.redirect(req.query.next or "/")

  utils.append_slash(app, "/profiles/icon_attribution")
  app.get '/profiles/icon_attribution/', (req, res) ->
    res.render 'home/profiles/icon_attribution', context(req, {
      title: "Icon Attribution"
    }, {active_name: "Icons"})

  utils.append_slash(app, "/profiles/login")
  app.get '/profiles/login/', (req, res) ->
    if utils.is_authenticated(req.session)
      return res.redirect(req.query.next or "/")
    res.render 'home/profiles/login', context(req, {
      title: "Sign in"
      next: req.query.next
    }, {active_name: "Sign In"})

  utils.append_slash(app, "/profiles/logout")
  app.get '/profiles/logout/', (req, res) ->
    api_methods.clear_session_auth(req.session)
    res.render 'home/profiles/logout', context(req, {
      title: "Logging out..."
    })

  utils.append_slash(app, "/groups/new", ["get", "post"])
  app.get '/groups/new/', (req, res) ->
    unless utils.is_authenticated(req.session)
      req.flash("info", "Please sign in to add a group.")
      return www_methods.redirect_to_login(req, res)

    res.render 'home/groups/edit', context(req, {
      title: "New group"
      group: {}
    }, {active_name: "Groups"})

  get_group_update_params = (req, cb) ->
    form = new multiparty.Form()
    form.parse req, (err, fields, files) ->
      return cb(err) if err?
      try
        member_changeset = JSON.parse(fields.member_changeset[0] or "{}")
      catch e
        return cb(e)
      group_update = {
        name: fields.name[0]
        remove_logo: if fields.remove_logo then fields.remove_logo[0] else null
        member_changeset: member_changeset
      }
      if files.logo and files.logo[0] and files.logo[0].headers['content-type']
        file = files.logo[0]
        if file.headers['content-type'].substring(0, 'image/'.length) == 'image/'
          group_update.logo_file = file
      cb(null, group_update)

  app.post '/groups/new/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.redirect_to_login(req, res)

    get_group_update_params req, (err, group_update) ->
      return www_methods.handle_error(req, res, err) if err?
      www_methods.create_group req.session, group_update, (err, group) ->
        return www_methods.handle_error(req, res, err) if err?
        return res.redirect("/groups/show/#{group.slug}/")

  utils.append_slash(app, "/groups/is_available")
  app.get '/groups/is_available/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.permission_denied(req, res)
    unless req.query.slug?
      return www_methods.ajax_bad_request(req, res, "Missing required 'slug' param")
    schema.Group.findOne {slug: utils.slugify(req.query.slug)}, "_id", (err, doc) ->
      return www_methods.ajax_handle_error(req, res, 'Server error') if err?
      res.send({available: (not doc?) or doc.id == req.query._id})

  utils.append_slash(app, "/groups/edit/[^/]+", ["get", "post"])
  app.get '/groups/edit/:slug/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.redirect_to_login(req, res)

    schema.Group.findOne({slug: req.params.slug}).populate('members.user').exec (err, doc) ->
      return www_methods.handle_error(req, res) if err?
      unless doc?
        return www_methods.not_found(req, res)

      membership = _.find doc.members, (m) -> m.user.email == req.session.auth.email
      unless membership?
        return www_methods.permission_denied(req, res)
      res.render 'home/groups/edit', context(req, {
        title: "Edit " + doc.name
        group: doc
      }, {active_name: "Groups"})

  app.post '/groups/edit/:slug/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.permission_denied(req, res)

    schema.Group.findOne {slug: req.params.slug}, (err, group) ->
      return www_methods.handle_error(req, res) if err?
      return www_methods.not_found(req, res) unless group?

      # Ensure that we are a member of this group.
      membership = _.find group.members, (m) -> m.user.toString() == req.session.auth.user_id
      return www_methods.permission_denied(req, res) unless membership?

      get_group_update_params req, (err, group_update) ->
        return www_methods.handle_error(req, res, err) if err
        www_methods.update_group req.session, group, group_update, (err) ->
          return www_methods.handle_error(req, res, err) if err?
          return res.redirect("/groups/show/#{group.slug}/")

  utils.append_slash(app, "/groups/join/[^/]+", ["get", "post"])
  app.get '/groups/join/:slug/', (req, res) ->
    unless utils.is_authenticated(req.session)
      req.flash("info", "You must sign in to join a group.")
      return www_methods.redirect_to_login(req, res)
    www_methods.verify_invitation req.session, req.params.slug, (err, group, invitation) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless group?
      unless invitation?
        membership = _.find group.members, (m) ->
          m.user.toString() == req.session.auth.user_id
        if membership
          # They are already a member; just redirect to the group display page.
          return res.redirect("/groups/show/#{group.slug}/")
        return res.render 'home/groups/bad_invite', context(req, {
          title: "Invitation not found"
          email: req.session.auth.email
        })

      user_ids = []
      for m in group.members
        user_ids.push(m.user)
      schema.User.find {_id: {$in: user_ids}}, (err, users) ->
        return www_methods.handle_error(req, res, err) if err?
        return www_methods.not_found(req, res) unless group?
        return res.render 'home/groups/join', context(req, {
          title: "Join " + group.name
          group: group
          users: users
        }, {active_name: "Groups"})

  app.post '/groups/join/:slug/', (req, res) ->
    www_methods.verify_invitation req.session, req.params.slug, (err, group, invitation) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless invitation?

      accepted = !!req.body.accept

      www_methods.process_invitation req.session, group, accepted, (err) ->
        return www_methods.handle_error(req, res, err) if err?
        if accepted
          req.session.groups ?= {}
          req.session.groups[group.id] = group
          req.flash("success", "Welcome to #{group.name}!")
        else
          req.flash("success", "Invitation successfully declined.")
        return res.redirect("/")


  utils.append_slash(app, "/groups/show/([^/]+)")
  app.get '/groups/show/:slug/', (req, res) ->
    unless utils.is_authenticated(req.session)
      req.flash("info", "You must sign in to see this group.")
      return www_methods.redirect_to_login(req, res)
    schema.Group.findOne {slug: req.params.slug}, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      # Verify that the user is a member of the group.  Non-members can never
      # view a group's details, unlike other documents.
      unless _.find(doc.members, (m) -> m.user.toString() == req.session.auth.user_id)
        return www_methods.permission_denied(req, res)
      async.parallel [
        (done) ->
          schema.SearchIndex.find({
            'sharing.group_id': doc._id
            'trash': {$ne: true}
          }).sort('-modified').exec done

        (done) ->
          www_methods.get_group_events(req.session, doc, done)

      ], (err, results) ->
        return www_methods.handle_error(req, res, err) if err?
        [search_indexes, events] = results
        res.render "home/groups/show", context(req, {
          title: doc.name
          group: doc
        }, {
          active_name: "Groups"
          group: doc
          events: events
          docs: search_indexes
        })

  app.get "/r/:shortpath", (req, res) ->
    schema.ShortURL.findOne { short_path: req.params.shortpath }, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      unless doc? and config.apps[doc.application]?
        return www_methods.not_found(req, res)
      res.redirect(doc.absolute_long_url)

  utils.append_slash(app, "/activity/for/.*[^/]$")
  app.get '/activity/for/:year/:month/:day/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.redirect_to_login(req, res)
    start = new Date(
      parseInt(req.params.year, 10),
      parseInt(req.params.month, 10) - 1,
      parseInt(req.params.day, 10),
      0, 0, 0
    )
    return www_methods.not_found(req, res) if isNaN(start)
    end = new Date(start.getTime() + (24 * 60 * 60 * 1000))

    prev = new Date(start.getTime() - 23 * 60 * 60 * 1000)
    prev_url = "/activity/for/#{prev.getFullYear()}/#{prev.getMonth() + 1}/#{prev.getDate()}/"
    next = new Date(start.getTime() + 26 * 60 * 60 * 1000)
    next_url = "/activity/for/#{next.getFullYear()}/#{next.getMonth() + 1}/#{next.getDate()}/"

    api_methods.get_event_user_hierarchy {
      start: start
      end: end
      groups: req.session.groups
      users: req.session.users
      user_id: req.session.auth.user_id
    }, (err, hierarchy, notices) ->
      return www_methods.handle_error(req, res, err) if err?
      res.render "home/daily_activity", context(req, {
        title: "Activity for #{req.params.year}-#{req.params.month}-#{req.params.day}"
        date: start
        start: start
        end: end
        hierarchy: hierarchy
        notices: notices
        prev_url: prev_url
        next_url: next_url
        show_url: req.url
        subscription_settings_link: config.api_url + "/profiles/edit/"
      })

  #
  # Static and well-known
  #
  app.get "/robots.txt", (req, res) ->
    res.setHeader('Content-Type', 'text/plain; charset=utf-8')
    res.send("User-agent: *\nDisallow:")

  #
  # Testing
  #
  if process.env.NODE_ENV != "production"
    utils.append_slash(app, "/test")
    app.get '/test/', (req, res) ->
      res.render 'test', context(req, {title: "Test"})
    app.get '/test/sockets/', (req, res) ->
      res.render 'test_sockets', context(req, {title: "Test"})

    utils.append_slash(app, "/500")
    app.get '/500/', (req, res) -> throw new Error("Test error, ignore")

    utils.append_slash(app, "/403")
    app.get '/403/', (req, res) -> www_methods.permission_denied(req, res)

    app.get '/test/notices/invitation/', (req, res) ->
      recipient = {email: "superhappypants@example.com"}
      if req.query.named
        recipient.name = "Super Happypants"
      email_notices.render_notifications require("../emails/invitation"), {
        group: {name: "The Awesomest Group"}
        sender: {name: "John Dough", email: "johndough@example.com"}
        recipient: recipient
        url: config.api_url + "/groups/join/the-awesomest-group"
        application: "www"
      }, (err, rendered) ->
        return www_methods.handle_error(req, res, err) if err?
        res.render('test_notice', rendered)

    app.get '/test/notices/new_proposal/', (req, res) ->
      email_notices.render_notifications require("../plugins/resolve/emails/new_proposal"), {
        group: {name: "The Awesomest Group"}
        sender: {name: "John Dough"}
        recipient: {name: "Super Happypants"}
        url: config.api_url + "/resolve/p/123"
        application: "resolve"
        proposal: {revisions: [{text: "Be it resolved, that this testy thing shows us exactly what we need to see to know that this thing is working the way we know that we see we think it should."}]}
      }, (err, rendered) ->
        return www_methods.handle_error(req, res, err) if err?
        res.render("test_notice", rendered)

    app.get '/test/notices/proposal_changed/', (req, res) ->
      email_notices.render_notifications require("../plugins/resolve/emails/proposal_changed"), {
        group: {name: "The Awesomest Group"}
        sender: {name: "John Dough"}
        recipient: {name: "Super Happypants"}
        url: config.api_url + "/resolve/p/123"
        application: "resolve"
        proposal: {revisions: [{text: "Be it resolved, that this testy thing shows us exactly what we need to see to know that this thing is working the way we know that we see we think it should."}]}
      }, (err, rendered) ->
        return www_methods.handle_error(req, res, err) if err?
        res.render("test_notice", rendered)

    app.get '/test/notices/daily_summary/', (req, res) ->
      unless utils.is_authenticated(req.session)
        return www_methods.redirect_to_login(req, res)
      schema.User.findOne {_id: req.session.auth.user_id}, (err, user) ->
        return www_methods.handle_error(req, res, err) if err?
        user.notifications.activity_summaries.sms = true
        user.notifications.activity_summaries.email = true
        email_notices.render_daily_activity_summary user, new Date(), (err, formats) ->
          return www_methods.handle_error(req, res, err) if err?
          return res.send("formats was undefined. Have no activity?") unless formats?
          formats.web = ""
          res.render("test_notice", formats)

  return {app}

route_errors = (config, app) ->
  ###
  Be sure to include this *after* everything else, as it intercepts all
  otherwise un-rotued URLs.  Also, make sure any static/asset middleware is
  loaded *before* any routing, so that the routing middleware comes last.
  ###
  www_methods = require("./www_methods")(config)
  app.use (err, req, res, next) ->
    if err?
      www_methods.handle_error(req, res, err)
    else
      next()
  app.get /.*/, www_methods.not_found


module.exports = {route, route_errors}
