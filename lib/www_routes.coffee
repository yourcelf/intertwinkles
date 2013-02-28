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

  #
  # Routes
  #

  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "www"},
        utils.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: utils.clean_conf(config)
      flash: req.flash(),
    }, obj)

  #
  # About pages
  #

  app.get '/', (req, res) ->
    # Show the landing page if we're not signed in.
    hero_apps =  ["firestarter", "twinklepad", "dotstorm", "resolve"]
    if not utils.is_authenticated(req.session)
      return res.render 'home/landing', context(req, {
        title: "InterTwinkles: Twinkling all over the InterWebs"
        hero_apps: hero_apps
      })

    # Show the dashboard if we are signed in.
    async.parallel [
      (done) -> www_methods.get_user_events(req.session, done)
      (done) -> www_methods.get_group_events(req.session, done)
      (done) -> utils.list_group_documents(
          schema.SearchIndex, req.session, done, {}, "-modified", 0, 20, true
        )
    ], (err, results) ->
      return www_methods.handle_error(req, res, err) if err?
      [user_events, group_events, recent_docs] = results
      if user_events.length == group_events.length == recent_docs.length == 0
        return res.redirect("/starting/")
      res.render 'home/dashboard', context(req, {
        title: "InterTwinkles"
        hero_apps: hero_apps
        activity: {
          user: user_events
          group: group_events
          docs: recent_docs
        }
        groups: req.session.groups
      })

  utils.append_slash(app, "/starting")
  app.get '/starting/', (req, res) ->
    res.render 'home/starting', context(req, {
      title: "Getting Started with InterTwinkles"
    })

  utils.append_slash(app, "/more")
  app.get '/more/', (req, res) ->
    res.render 'home/more', context(req, {
      title: "More InterTwinkles"
    })

  utils.append_slash(app, "/about")
  app.get '/about/', (req, res) ->
    res.render 'home/about/index', context(req, {
      title: "About InterTwinkles"
    })

  utils.append_slash(app, "/about/terms")
  app.get '/about/terms/', (req, res) ->
    res.render 'home/about/terms', context(req, {
      title: "Terms of Use"
    })

  utils.append_slash(app, "/about/privacy")
  app.get '/about/privacy/', (req, res) ->
    res.render 'home/about/privacy', context(req, {
      title: "Privacy Policy"
    })

  utils.append_slash(app, "/about/related")
  app.get '/about/related/', (req, res) ->
    res.render 'home/about/related', context(req, {
      title: "Related Work"
    })

  #
  # Testing
  #
  utils.append_slash(app, "/test")
  app.get '/test/', (req, res) ->
    res.render 'test', context(req, {title: "Test"})

  utils.append_slash(app, "/500")
  app.get '/500/', (req, res) -> throw new Error("Test error, ignore")

  utils.append_slash(app, "/403")
  app.get '/403/', (req, res) -> www_methods.permission_denied(req, res)

  #
  # Search
  #

  utils.append_slash(app, "/search")
  app.get '/search/', (req, res) ->
    respond = (err, docs) ->
      return www_methods.handle_error(req, res, err) if err?
      res.render 'home/search', context(req, {
        authenticated: utils.is_authenticated(req.session)
        title: "Search",
        docs: docs
        highlighting: results?.highlighting
        q: req.query.q
      })

    return respond(null, []) unless req.query.q

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
      }
      res.render 'home/profiles/edit', context(req, {
        title: "Profile settings"
        user: user
        carrier_list: _.keys(carriers)
      })

  app.post '/profiles/edit/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.permission_denied(req, res)
    www_methods.edit_profile req.session, req.body, (err, user) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.permission_denied(req, res) unless user?
      return res.redirect(req.query.next or "/")

  utils.append_slash(app, "/profiles/icon_attribution")
  app.get '/profiles/icon_attribution/', (req, res) ->
    res.render 'home/profiles/icon_attribution', context(req, {
      title: "Icon Attribution"
    })

  utils.append_slash(app, "/profiles/login")
  app.get '/profiles/login/', (req, res) ->
    if utils.is_authenticated(req.session)
      return res.redirect(req.query.next or "/")
    res.render 'home/profiles/login', context(req, {
      title: "Sign in"
      next: req.query.next
    })

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
    })

  get_group_update_params = (req) ->
    group_update = {
      name: req.body.name
      remove_logo: req.body.remove_logo
      member_changeset: JSON.parse(req.body.member_changeset or "{}")
    }
    if req.files.logo.size > 0 and req.files.logo.type.substring(0, 'image/'.length) == 'image/'
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
      return res.redirect("/groups/edit/#{group.slug}")

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
        return not_found(req, res)

      membership = _.find doc.members, (m) -> m.user.email == req.session.auth.email
      unless membership?
        return www_methods.permission_denied(req, res)
      res.render 'home/groups/edit', context(req, {
        title: "Edit " + doc.name
        group: doc
      })

  app.post '/groups/edit/:slug/', (req, res) ->
    unless utils.is_authenticated(req.session)
      return www_methods.permission_denied(req, res)

    schema.Group.findOne {slug: req.params.slug}, (err, doc) ->
      return www_methods.handle_error(req, res) if err?
      return not_found(req, res) unless doc?

      # Ensure that we are a member of this group.
      user = _.find(req.session.users, (u) -> u.email == req.session.auth.email)
      membership = _.find doc.members, (m) -> m.user.email == user.email
      unless membership?
        return www_methods.permission_denied(req, res)

      try
        group_update = get_group_update_params(req)
      catch e
        return www_methods.handle_error(req, res, "Invalid JSON for member changeset")

      www_methods.update_group req.session, group, group_update, (err) ->
        return www_methods.handle_error(req, res, err) if err?
        return res.redirect("/groups/edit/#{group.slug}")

  utils.append_slash(app, "/groups/join/[^/]+", ["get", "post"])
  app.get '/groups/join/:slug/', (req, res) ->
    unless utils.is_authenticated(session)
      req.flash("info", "You must sign in to join a group.")
      return www_methods.redirect_to_login(req, res)
    www_methods.verify_invitation req.session, req.params.slug, (err, group) ->
      return www_methods.handle_error(req, res, err) if err?
      return not_found(req, res) unless group?
      return res.render 'home/groups/join', context(req, {
        title: "Join " + group.name
        group: group
      })

  app.post '/groups/join/:slug/', (req, res) ->
    www_methods.verify_invitation req.session, req.params.slug, (err, group) ->
      return www_methods.handle_error(req, res, err) if err?
      return not_found(req, res) unless group?

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
      return not_found(req, res) unless doc?
      # Verify that the user is a member of the group.  Non-members can never
      # view a group's details, unlike other documents.
      unless _.find(doc.members, (m) -> m.user.toString() == req.session.auth.user_id)
        return www_methods.permission_denied(req, res)
      async.parallel [
        (done) ->
          schema.SearchIndex.find({
            'sharing.group_id': doc._id
          }).sort('-modified').exec done

      ], (err, results) ->
        [search_indexes] = results
        res.render "home/groups/show", context(req, {
          title: doc.name
          group: doc
          docs: search_indexes
        })

  return {app}

route_errors = (config, app) ->
  www_methods = require("./www_methods")(config)
  app.use (err, req, res, next) ->
    if err?
      www_methods.handle_error(req, res, err)
    else
      next()
  #XXX There should be a cleaner way to capture unrouted 404's.. This won't
  #work with the current strategy of directory-passing to connect-assets,
  #unless we can get connect-assets to work prior to the router.  This
  #intercepts all connect-assets urls currently.
  app.get /.*/, www_methods.not_found


module.exports = {route, route_errors}
