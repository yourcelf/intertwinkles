express        = require 'express'
socketio       = require 'socket.io'
mongoose       = require 'mongoose'
intertwinkles  = require '../../../lib/intertwinkles'
RoomManager    = require('iorooms').RoomManager
RedisStore     = require('connect-redis')(express)
_              = require 'underscore'
url            = require 'url'
etherpadClient = require 'etherpad-lite-client'
async          = require 'async'
logger         = require('log4js').getLogger()

start = (config, app, io, sessionStore) ->
  schema = require('./schema').load(config)
  api_methods = require('../../../lib/api_methods')(config)
  solr = require("../../../lib/solr_helper")(config)
  #
  # Sockets
  #
  iorooms = new RoomManager("/io-twinklepad", io, sessionStore)
  iorooms.authorizeJoinRoom = (session, name, callback) ->
    schema.TwinklePad.findOne {pad_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if intertwinkles.can_view(session, doc)
        callback(null)
      else
        callback("Permission denied")

  # Clear etherpad session on disconnect
  iorooms.on "disconnect", (data) ->
    session = data.socket.session
    if session?.etherpad_session_id
      etherpad.deleteSession {
        sessionID: session.etherpad_session_id
      }, (err, data) ->
        logger.error(err) if err?
        delete session.etherpad_session_id
        iorooms.saveSession session, (err) -> logger.error(err) if err?

  post_search_index = (doc, timeout=15000) ->
    etherpad.getText {padID: doc.pad_id}, (err, data) ->
      return logger.error(err) if err?
      text = data.text
      summary = text.substring(0, 200)
      if summary.length < text.length
        summary += "..."
      api_methods.add_search_index {
        application: "twinklepad"
        entity: doc._id
        type: "etherpad"
        url: "/twinklepad/p/#{doc.pad_name}"
        title: "#{doc.pad_name}"
        summary: summary
        text: text
        sharing: doc.sharing
      }, timeout

  iorooms.onChannel "save_twinklepad", (socket, data) ->
    respond = (err, doc) ->
      return socket.emit "error", {error: err} if err?
      doc.sharing = intertwinkles.clean_sharing(socket.session, doc)
      socket.broadcast.to(doc.pad_id).emit "twinklepad", {twinklepad: doc}
      socket.emit "twinklepad", {twinklepad: doc}

    unless data.twinklepad?._id? and data.twinklepad?.sharing?
      return respond("Missing twinklepad params")

    schema.TwinklePad.findOne {_id: data.twinklepad._id}, (err, doc) ->
      return respond(err) if err?
      return respond("Twinklepad not found for #{data.twinklepad.pad_id}") unless doc?
      return respond("Permission denied") unless intertwinkles.can_change_sharing(
        socket.session, doc
      )
      doc.sharing = data.twinklepad.sharing
      return respond("Permission denied") unless intertwinkles.can_change_sharing(
        socket.session, doc
      )
      doc.save(respond)
      # Re-index immediately, so that search permissions are updated.
      post_search_index(doc, 0)

  # When we arrive at a pad, the client joins a room for the pad ID.  When we
  # leave the room, post a search index of the latest pad text.
  iorooms.on "leave", (data) ->
    session = data.socket.session
    pad_id = data.room
    schema.TwinklePad.findOne {pad_id: pad_id}, (err, doc) ->
      return logger.error(err) if err?
      post_search_index(doc, 15000)

  #
  # Routes
  #
  
  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "twinklepad"},
        intertwinkles.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: intertwinkles.clean_conf(config)
      flash: req.flash()
    }, obj)

  server_error = (req, res, err) ->
    res.statusCode = 500
    logger.error(err)
    return res.send("Server error") # TODO pretty 500 page

  not_found = (req, res) ->
    return res.send("Not found", 404) # TODO pretty 404 page

  permission_denied = (req, res) ->
    return res.send("Permission denied", 403) # TODO pretty 403 page

  pad_url_parts = url.parse(config.apps.twinklepad.etherpad.url)
  etherpad = etherpadClient.connect({
    apikey: config.apps.twinklepad.etherpad.api_key
    host: pad_url_parts.hostname
    port: pad_url_parts.port
  })

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
        if intertwinkles.is_authenticated(req.session)
          solr.execute_search {
            public: false
            
            application: "twinklepad"
            sort: "modified desc"
          }, req.session.auth.user_id, (err, results) ->
            done(err, results?.response?.docs)
        else
          done(null, [])
    ], (err, results) ->
      return server_error(req, res, err) if err?
      res.render 'twinklepad/index', context(req, {
        title: "#{config.apps.twinklepad.name}"
        is_authenticated: intertwinkles.is_authenticated(req.session)
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
    # the user breaks their iorooms websocket (above).
    #
    # http://etherpad.org/doc/v1.2.1/#index_overview
    #
    async.waterfall [
      # Retrieve and maybe create the pad.
      (done) ->
        schema.TwinklePad.findOne {pad_name: req.params.pad_name}, (err, doc) ->
          return server_error(req, res, err) if err?
          if not doc?
            doc = new schema.TwinklePad {pad_name: req.params.pad_name}
            doc.save(done)
          else
            done(null, doc)

    ], (err, doc) ->
      return server_error(req, res, err) if err?

      # Check that we can view this pad.
      if intertwinkles.can_edit(req.session, doc)
        read_only = false
      else if intertwinkles.can_view(req.session, doc)
        read_only = true
      else
        return permission_denied(req, res)

      # Post a view event to intertwinkles.
      api_methods.post_event {
        application: "twinklepad"
        type: "visit"
        entity_url: "/twinklepad/p/#{doc.pad_name}"
        entity: doc._id
        user: req.session.auth?.user_id
        anon_id: req.session.anon_id
        group: doc.sharing?.group_id
        data: {
          title: doc.pad_name
          action: read_only
        }
      }, 1000 * 60 * 5, (->)

      doc.sharing = intertwinkles.clean_sharing(req.session, doc)
      title = "#{req.params.pad_name} | #{config.apps.twinklepad.name}"

      #
      # Display read only.
      #
      if read_only
        etherpad.getHTML {padID: doc.pad_id}, (err, data) ->
          res.render "twinklepad/pad", context(req, {
            title: title
            embed_url: null
            text: data.html
          }, {
            read_only: read_only
            twinklepad: doc
          })
        return
      
      #
      # Display editable. Establish an etherpad auth session.
      #
      
      # Get the author mapper / author name
      etherpad.createAuthorIfNotExistsFor {
        authorMapper: req.session.auth?.user_id or req.session.anon_id
        name: req.session.users?[req.session.auth.user_id]?.name
      }, (err, data) ->
        return server_error(req, res, err) if err?
        author_id = data.authorID

        # Set an arbitrary session length of 1 day; though that only matters if
        # the user leaves a tab open and connected for that long.
        maxAge = 24 * 60 * 60
        valid_until = (new Date().getTime()) + maxAge
        if doc.public_edit_until? or doc.public_view_until?
          valid_until = Math.min(valid_until,
            new Date(doc.public_edit_until or doc.public_view_until).getTime())

        etherpad.createSession {
          groupID: doc.etherpad_group_id
          authorID: author_id
          validUntil: valid_until
        }, (err, data) ->
          return server_error(req, res, err) if err?
          req.session.etherpad_session_id = data.sessionID
          logger.log config.apps.twinklepad.etherpad.cookie_domain
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
          res.cookie("sessionID", data.sessionID, cookie_params)
          embed_url = doc.url
          if intertwinkles.is_authenticated(req.session)
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

module.exports = {start}
