express        = require 'express'
socketio       = require 'socket.io'
mongoose       = require 'mongoose'
intertwinkles  = require 'node-intertwinkles'
RoomManager    = require('iorooms').RoomManager
RedisStore     = require('connect-redis')(express)
_              = require 'underscore'
url            = require 'url'
etherpadClient = require 'etherpad-lite-client'
async          = require 'async'

start = (config) ->
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )
  schema = require('./schema').load(config)
  sessionStore = new RedisStore()
  app = express.createServer()

  #
  # Config
  #
  
  app.configure ->
    app.use require('connect-assets')()
    app.use express.bodyParser()
    app.use express.cookieParser()
    app.use express.session
      secret: config.secret
      key: 'express.sid'
      store: sessionStore

  app.configure 'development', ->
      app.use '/static', express.static(__dirname + '/../assets')
      app.use '/static', express.static(__dirname + '/../node_modules/node-intertwinkles/assets')
      app.use express.errorHandler {dumpExceptions: true, showStack: true}

  app.configure 'production', ->
    # Cache long time in production.
    app.use '/static', express.static(__dirname + '/../assets', { maxAge: 1000*60*60*24 })
    app.use '/static', express.static(__dirname + '/../node_modules/node-intertwinkles/assets', { maxAge: 1000*60*60*24 })

  app.set 'view engine', 'jade'
  app.set 'view options', {layout: false}

  #
  # Sockets
  #

  io = socketio.listen(app, {"log level": 0})
  iorooms = new RoomManager("/iorooms", io, sessionStore)
  intertwinkles.attach(config, app, iorooms)
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
        console.error(err) if err?
        delete session.etherpad_session_id
        iorooms.saveSession session, (err) -> console.error(err) if err?

  post_search_index = (doc, timeout=15000) ->
    etherpad.getText {padID: doc.pad_id}, (err, data) ->
      return console.error(err) if err?
      text = data.text
      summary = text.substring(0, 200)
      if summary.length < text.length
        summary += "..."
      intertwinkles.post_search_index {
        application: "twinklepad"
        entity: doc._id
        type: "etherpad"
        url: "/p/#{doc.pad_name}"
        title: "#{doc.pad_name}"
        summary: summary
        text: text
        sharing: doc.sharing
      }, config, null, timeout

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
      return console.error(err) if err?
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
    console.error(err)
    return res.send("Server error") # TODO pretty 500 page

  not_found = (req, res) ->
    return res.send("Not found", 404) # TODO pretty 404 page

  permission_denied = (req, res) ->
    return res.send("Permission denied", 403) # TODO pretty 403 page

  pad_url_parts = url.parse(config.etherpad.url)
  etherpad = etherpadClient.connect({
    apikey: config.etherpad.api_key
    host: pad_url_parts.hostname
    port: pad_url_parts.port
  })

  app.get '/', (req, res) ->
    async.parallel [
      (done) ->
        intertwinkles.search {
          public: true
          application: "twinklepad"
          sort: "modified desc"
        }, config, (err, results) ->
          done(err, results?.response?.docs)

      (done) ->
        if intertwinkles.is_authenticated(req.session)
          intertwinkles.search {
            public: false
            user: req.session.auth.user_id
            application: "twinklepad"
            sort: "modified desc"
          }, config, (err, results) ->
            done(err, results?.response?.docs)
        else
          done(null, [])
    ], (err, results) ->
      return server_error(req, res, err) if err?
      res.render 'index', context(req, {
        title: "#{config.apps.twinklepad.name}"
        is_authenticated: intertwinkles.is_authenticated(req.session)
        listed_pads: {
          public: results[0]
          group: results[1]
        }
      })

  app.get '/p/:pad_name', (req, res) ->
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
      intertwinkles.post_event {
        application: "twinklepad"
        type: "visit"
        entity_url: "/p/#{doc.pad_name}"
        entity: doc._id
        user: req.session.auth?.user_id
        anon_id: req.session.anon_id
        group: doc.sharing?.group_id
        data: {
          title: doc.pad_name
          action: read_only
        }
      }, config, (->), 1000 * 60 * 5

      doc.sharing = intertwinkles.clean_sharing(req.session, doc)
      title = "#{req.params.pad_name} | #{config.apps.twinklepad.name}"

      #
      # Display read only.
      #
      if read_only
        etherpad.getHTML {padID: doc.pad_id}, (err, data) ->
          res.render "pad", context(req, {
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
          res.cookie("sessionID", data.sessionID, {
            maxAge: maxAge
            domain: config.etherpad.cookie_domain
          })
          embed_url = doc.url
          if intertwinkles.is_authenticated(req.session)
            author_color = req.session.users[req.session.auth.user_id].icon?.color
            author_name = req.session.users[req.session.auth.user_id].name
            embed_url += "?userName=#{author_name}&userColor=%23#{author_color}"
          res.render "pad", context(req, {
            title: "#{req.params.pad_name} | #{config.apps.twinklepad.name}"
            embed_url: embed_url
            text: null
          }, {
            read_only: read_only
            twinklepad: doc
          })

  app.listen (config.port)

module.exports = {start}
