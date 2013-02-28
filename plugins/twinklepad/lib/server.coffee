utils          = require '../../../lib/utils'
_              = require 'underscore'
url            = require 'url'
etherpadClient = require 'etherpad-lite-client'
async          = require 'async'
logger         = require('log4js').getLogger()

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  api_methods = require('../../../lib/api_methods')(config)
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
    [channel, name] = room.split("/")
    unless last and session.etherpad_session_id? and channel == "twinklepad"
      return
    # Update the search index.
    schema.TwinklePad.findOne {pad_id: name}, (err, doc) ->
      return logger.error(err) if err?
      post_search_index(doc)
    # Remove the session's etherpad_session_id.
    etherpad.deleteSession {
      sessionID: session.etherpad_session_id
    }, (err, data) ->
      logger.error(err) if err?
      delete session.etherpad_session_id
      sockrooms.saveSession session, (err) -> logger.error(err) if err?

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
        url: "/p/#{doc.pad_name}"
        title: "#{doc.pad_name}"
        summary: summary
        text: text
        sharing: doc.sharing
      }, timeout

  sockrooms.on "twinklepad/save_twinklepad", (socket, session, data) ->
    respond = (err, doc) ->
      return socket.sendJSON "error", {error: err} if err?
      doc.sharing = utils.clean_sharing(session, doc)
      sockrooms.broadcast "twinklepad/" + doc.pad_id, "twinklepad", {twinklepad: doc}

    unless data.twinklepad?._id? and data.twinklepad?.sharing?
      return respond("Missing twinklepad params")

    schema.TwinklePad.findOne {_id: data.twinklepad._id}, (err, doc) ->
      return respond(err) if err?
      return respond("Twinklepad not found for #{data.twinklepad.pad_id}") unless doc?
      return respond("Permission denied") unless utils.can_change_sharing(
        session, doc
      )
      doc.sharing = data.twinklepad.sharing
      return respond("Permission denied") unless utils.can_change_sharing(
        session, doc
      )
      doc.save(respond)
      # Re-index immediately, so that search permissions are updated.
      post_search_index(doc, 0)


  #
  # Routes
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
          return www_methods.handle_error(req, res, err) if err?
          if not doc?
            doc = new schema.TwinklePad {pad_name: req.params.pad_name}
            doc.save(done)
          else
            done(null, doc)

    ], (err, doc) ->
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

      # Post a view event to intertwinkles.
      api_methods.post_event {
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
      }, 1000 * 60 * 5, (->)

      doc.sharing = utils.clean_sharing(req.session, doc)
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
        return www_methods.handle_error(req, res, err) if err?
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
          return www_methods.handle_error(req, res, err) if err?
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

module.exports = {start}
