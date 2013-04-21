utils          = require '../../../lib/utils'
_              = require 'underscore'
url            = require 'url'
async          = require 'async'
logger         = require('log4js').getLogger()

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  padlib = require("./padlib")(config)
  www_methods = require("../../../lib/www_methods")(config)
  solr = require("../../../lib/solr_helper")(config)

  #
  # Sockets
  #
  sockrooms.addChannelAuth "twinklepad", (session, room, callback) ->
    name = room.split("/")[1]
    schema.TwinklePad.findOne {pad_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      return callback("Twinklepad #{name} not found") unless doc?
      if utils.can_view(session, doc)
        callback(null, true)
      else
        callback(null, false)

  # When we arrive at a pad, the client joins a room for the pad ID.  When we
  # leave the room, post a search index of the latest pad text, and remove the
  # etherpad session id.
  sockrooms.on "leave", (data) ->
    {socket, session, room, last} = data
    [channel, pad_id] = room.split("/")
    unless last and session.etherpad_session_id? and channel == "twinklepad"
      return
    padlib.leave_pad socket, session, pad_id, (err) ->
      logger.error(err) if err?
      if session.etherpad_session_id?
        delete session.etherpad_session_id
        sockrooms.saveSession session, (err) ->
          logger.error(err) if err?

  sockrooms.on "twinklepad/save_twinklepad", (socket, session, data) ->
    padlib.save_pad session, data, (err, doc) ->
      return socketrooms.handleError(socket, err) if err?
      doc.sharing = utils.clean_sharing(session, doc)
      sockrooms.broadcast "twinklepad/" + doc.pad_id, "twinklepad", {twinklepad: doc}

  #
  # HTTP Routes
  #
  
  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "twinklepad"},
        utils.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: utils.clean_conf(config)
      flash: req.flash()
    }, obj)

  app.get /\/twinklepad$/, (req, res) -> res.redirect('/twinklepad/')
  app.get '/twinklepad/', (req, res) ->
    async.parallel [
      (done) ->
        solr.execute_search {
          public: true
          application: "twinklepad"
          sort: "modified desc"
        }, null, (err, results) ->
          done(err, results?.response?.docs)

      (done) ->
        if utils.is_authenticated(req.session)
          solr.execute_search {
            public: false
            application: "twinklepad"
            sort: "modified desc"
          }, req.session.auth.user_id, (err, results) ->
            done(err, results?.response?.docs)
        else
          done(null, [])
    ], (err, results) ->
      return www_methods.handle_error(req, res, err) if err?
      for result in results[0]
        result.absolute_url = config.apps.twinklepad.url + result.url
      for result in results[1]
        result.absolute_url = config.apps.twinklepad.url + result.url
      res.render 'twinklepad/index', context(req, {
        title: "#{config.apps.twinklepad.name}"
        is_authenticated: utils.is_authenticated(req.session)
        listed_pads: {
          public: results[0]
          group: results[1]
        }
      })

  app.get '/twinklepad/p/:pad_name', (req, res) ->
    #
    # The strategy for authorizing access to InterTwinkles etherpads is to use
    # the Etherpad API to create one group per pad, and to add a one-time-use
    # session for each user on every pad page load. The session is cleared when
    # the user leaves and hence breaks their socket (above).
    #
    # http://etherpad.org/doc/v1.2.1/#index_overview
    #
    async.waterfall [
      # Retrieve and maybe create the pad.
      (done) ->
        schema.TwinklePad.findOne {pad_name: req.params.pad_name}, (err, doc) ->
          return done(err) if err?
          if not doc?
            doc = new schema.TwinklePad {pad_name: req.params.pad_name}
            doc.save (err, doc) ->
              done(err, doc, "create")
          else
            done(null, doc, "visit")

    ], (err, doc, event_type) ->
      return www_methods.handle_error(req, res, err) if err?

      # Check that we can view this pad.
      if utils.can_edit(req.session, doc)
        read_only = false
      else if utils.can_view(req.session, doc)
        read_only = true
      else if utils.is_authenticated(req.session)
        return www_methods.permission_denied(req, res)
      else
        return www_methods.redirect_to_login(req, res)

      # Post event to intertwinkles.
      async.parallel [
        (done) ->
          timeout = if event_type == "visit" then 1000 * 60 * 5 else 0
          padlib.post_twinklepad_event(req.session, doc, event_type, {}, timeout, done)

        (done) ->
          doc.sharing = utils.clean_sharing(req.session, doc)
          title = "#{req.params.pad_name} | #{config.apps.twinklepad.name}"

          if read_only
            # Display read only.
            padlib.get_read_only_html doc, (err, html)->
              return done(err) if err?
              res.render "twinklepad/pad", context(req, {
                title: title
                embed_url: null
                text: html
              }, {
                read_only: read_only
                twinklepad: doc
              })
              return done()
          else
            # Display editable. Establish an etherpad auth session.
            # Get the author mapper / author name
            maxAge = 24 * 60 * 60 * 1000
            padlib.create_pad_session req.session, doc, maxAge, (err, pad_session_id) ->
              return done(err) if err?
              req.session.etherpad_session_id = pad_session_id
              cookie_params = {
                path: "/"
                maxAge: maxAge
                domain: config.apps.twinklepad.etherpad.cookie_domain
              }
              # HACK: Chromium 20 seems to fail to set the cookie when domains are
              # the same (at least for localhost) -- so remove the domain param if
              # it isn't needed.
              if (url.parse(config.apps.twinklepad.url).hostname ==
                  url.parse(config.apps.twinklepad.etherpad.url).hostname)
                delete cookie_params.domain
              res.cookie("sessionID", pad_session_id, cookie_params)
              embed_url = doc.url
              if utils.is_authenticated(req.session)
                author_color = req.session.users[req.session.auth.user_id].icon?.color
                author_name = req.session.users[req.session.auth.user_id].name
                embed_url += "?userName=#{author_name}&userColor=%23#{author_color}"
              res.render "twinklepad/pad", context(req, {
                title: "#{req.params.pad_name} | #{config.apps.twinklepad.name}"
                embed_url: embed_url
                text: null
              }, {
                read_only: read_only
                twinklepad: doc
              })
              return done()

      ], (err) ->
        return www_methods.handle_error(req, res, err) if err?

module.exports = {start}
