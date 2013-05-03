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
    schema.TwinklePad.findOne {_id: name}, 'sharing', (err, doc) ->
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
    [channel, _id] = room.split("/")
    unless last and session.etherpad_session_id? and channel == "twinklepad"
      return
    padlib.leave_pad socket, session, _id, (err) ->
      logger.error(err) if err?
      if session.etherpad_session_id?
        delete session.etherpad_session_id
        sockrooms.saveSession session, (err) ->
          logger.error(err) if err?

  sockrooms.on "twinklepad/save_twinklepad", (socket, session, data) ->
    padlib.save_pad session, data, (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      orig_sharing = doc.sharing
      doc.sharing = utils.clean_sharing(session, doc)
      socket.sendJSON "twinklepad", {twinklepad: doc}
      sockrooms.roomSocketSessionMap "twinklepad/#{doc.id}", (err, socket, sess) ->
        return logger.error(err) if err?
        if sess.session_id != session.session_id
          doc.sharing = utils.clean_sharing(sess, {sharing: orig_sharing})
          socket.sendJSON("twinklepad", {twinklepad: doc})

  sockrooms.on "twinklepad/create_twinklepad", (socket, session, data) ->
    padlib.create_pad session, data, (err, doc, extras, event) ->
      return sockrooms.handleError(socket, err) if err?
      return socket.sendJSON("twinklepad", {
        twinklepad: _.extend(doc.toJSON(), extras)
      })

  sockrooms.on "twinklepad/fetch_twinklepad", (socket, session, data) ->
    padlib.fetch_pad session, {pad_name: data.pad_name}, (err, doc, extras, event) ->
      return sockrooms.handleError(socket, err or "Not found") if err? or not doc?
      ret = {twinklepad: _.extend(doc.toJSON(), extras)}
      sockrooms.saveSession session, (err) ->
        return sockrooms.handleError(err) if err?
        socket.sendJSON(extras)

  sockrooms.on "twinklepad/check_name", (socket, session, data) ->
    schema.TwinklePad.findOne {pad_name: data.pad_name}, '_id', (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      socket.sendJSON(data.callback or "twinklepad:check_name", {
        available: not doc?
      })

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

  index_res = (req, res, extraContext={}, initialData={}) ->
    # include extraContext as both 
    res.render 'twinklepad/index', context(req, _.extend({
      title: "#{config.apps.twinklepad.pad_name}"
    }, extraContext), initialData)

  utils.append_slash(app, '/twinklepad')
  app.get '/twinklepad/', (req, res) -> index_res(req, res)

  utils.append_slash(app, '/twinklepad/new')
  app.get '/twinklepad/new/', (req, res) -> index_res(req, res)

  utils.append_slash(app, '/twinklepad/p/.*[^/]$')
  app.get '/twinklepad/p/:pad_name/:action?/', (req, res) ->
    #
    # The strategy for authorizing access to InterTwinkles etherpads is to use
    # the Etherpad API to create one group per pad, and to add a one-time-use
    # session for each user on every pad page load. The session is cleared when
    # the user leaves and hence breaks their socket (above).
    #
    # http://etherpad.org/doc/v1.2.1/#index_overview
    #
    padlib.fetch_pad req.session, req.params, (err, doc, extras) ->
      if err == "Permission denied"
        if utils.is_authenticated(req.session)
          return www_methods.permission_denied(req, res)
        else
          return www_methods.redirect_to_login(req, res)
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?

      extraContext = {title: "#{doc.pad_name}"}
      initialData = {twinklepad: _.extend(doc.toJSON(), extras)}
      initialData.twinklepad.sharing = utils.clean_sharing(req.session, doc)
      return index_res(req, res, extraContext, initialData)

module.exports = {start}
