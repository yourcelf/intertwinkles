utils         = require './utils'
_             = require 'underscore'
async         = require 'async'
carriers      = require './carriers'
thumbnails    = require './thumbnails'
logger        = require('log4js').getLogger()

route = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  api_methods = require("./api_methods")(config)
  www_methods = require("./www_methods")(config)
  solr = require("./solr_helper")(config)
  render_notifications = require("./email_notices").load(config).render_notifications

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
            {"sharing.group_id": group_id}, "-modified", 0, 10, true
          )
        , done
    ], (err, results) ->
      return www_methods.handle_error(req, res, err) if err?
      [events, groups_docs] = results
      res.render 'home/dashboard', context(req, {
        title: "InterTwinkles"
      }, {
        active_name: "Groups",
        events: events,
        groups_docs: groups_docs
      })

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

  get_group_update_params = (req) ->
    group_update = {
      name: req.body.name
      remove_logo: req.body.remove_logo
      member_changeset: JSON.parse(req.body.member_changeset or "{}")
    }
    if req.files.logo?.size > 0 and req.files.logo.type.substring(0, 'image/'.length) == 'image/'
      group_update.logo_file = req.files.logo
    return group_update

  app.post '/groups/new/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.redirect_to_login(req, res)
    try
      group_update = get_group_update_params(req)
    catch e
      return www_methods.handle_error(req, res, "Invalid JSON for member changeset")
    www_methods.create_group req.session, group_update, (err, group) ->
      return www_methods.handle_error(req, res, err) if err?
      return res.redirect("/groups/show/#{group.slug}")

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
      unless membership?
        return www_methods.permission_denied(req, res)

      try
        group_update = get_group_update_params(req)
      catch e
        return www_methods.handle_error(req, res, "Invalid JSON for member changeset")

      www_methods.update_group req.session, group, group_update, (err) ->
        return www_methods.handle_error(req, res, err) if err?
        return res.redirect("/groups/show/#{group.slug}")

  utils.append_slash(app, "/groups/join/[^/]+", ["get", "post"])
  app.get '/groups/join/:slug/', (req, res) ->
    unless utils.is_authenticated(req.session)
      req.flash("info", "You must sign in to join a group.")
      return www_methods.redirect_to_login(req, res)
    www_methods.verify_invitation req.session, req.params.slug, (err, group) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless group?
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
    www_methods.verify_invitation req.session, req.params.slug, (err, group) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless group?

      accepted = !!req.body.accept

      www_methods.process_invitation req.session, group, accepted, (err) ->
        return www_methods.handle_error(req, res, err) if err?
        if accepted
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
      render_notifications require("../emails/invitation"), {
        group: {name: "The Awesomest Group"}
        sender: {name: "John Dough"}
        recipient: {name: "Super Happypants"}
        url: config.api_url + "/groups/join/the-awesomest-group"
        application: "www"
      }, (err, rendered) ->
        return www_methods.handle_error(req, res, err) if err?
        res.render('test_notice', rendered)

    app.get '/test/notices/new_proposal/', (req, res) ->
      render_notifications require("../plugins/resolve/emails/new_proposal"), {
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
      render_notifications require("../plugins/resolve/emails/proposal_changed"), {
        group: {name: "The Awesomest Group"}
        sender: {name: "John Dough"}
        recipient: {name: "Super Happypants"}
        url: config.api_url + "/resolve/p/123"
        application: "resolve"
        proposal: {revisions: [{text: "Be it resolved, that this testy thing shows us exactly what we need to see to know that this thing is working the way we know that we see we think it should."}]}
      }, (err, rendered) ->
        return www_methods.handle_error(req, res, err) if err?
        res.render("test_notice", rendered)

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
