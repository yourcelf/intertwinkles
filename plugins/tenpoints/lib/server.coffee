_             = require 'underscore'
utils         = require '../../../lib/utils'

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  www_methods = require("../../../lib/www_methods")(config)
  tenpoints = require("./tenpoints")(config)

  sockrooms.addChannelAuth "tenpoints", (session, room, callback) ->
    name = room.split("/")[1]
    schema.TenPoint.findOne {_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      return callback("TenPoint #{name} not found") unless doc?
      return callback(null, utils.can_view(session, doc))

  index_res = (req, res, initial_data={}) ->
    utils.list_accessible_documents schema.TenPoint, req.session, (err, docs) ->
      return www_methods.handle_error(req, res, err) if err?
      for doc in docs.group
        doc.sharing = utils.clean_sharing(req.session, doc)
      for doc in docs.public
        doc.sharing = utils.clean_sharing(req.session, doc)
      res.render 'tenpoints/index', {
        title: "Ten Points"
        initial_data: _.extend(
          {application: "tenpoints", ten_points_list: docs},
          utils.get_initial_data(req.session, config),
          initial_data
        )
        conf: utils.clean_conf(config)
        flash: req.flash()
      }

  #
  # Routes
  #

  utils.append_slash(app, "/tenpoints")
  app.get '/tenpoints/', (req, res) -> index_res(req, res)

  utils.append_slash(app, "/tenpoints/add")
  app.get '/tenpoints/add/', (req, res) -> index_res(req, res)

  utils.append_slash(app, "/tenpoints/10/.*[^/]$")
  app.get '/tenpoints/10/:slug/:tag?/', (req, res) ->
    schema.TenPoint.findOne {slug: req.params.slug}, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      unless utils.can_view(req.session, doc)
        if utils.is_authenticated(req.session)
          return www_methods.permission_denied(req, res)
        else
          return www_methods.redirect_to_login(req, res)

      tenpoints.post_event(req.session, doc, {type: "visit"}, 5 * 1000 * 60,
        (err, timeout) ->
          doc.sharing = utils.clean_sharing(req.session, doc)
          index_res(req, res, { tenpoint: doc.toJSON() })
      )

  #
  # Socket routes
  #

  sockrooms.on "tenpoints/fetch_tenpoint", (socket, session, data) ->
    tenpoints.fetch_tenpoint data.slug, session, (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      doc.sharing = utils.clean_sharing(session, doc)
      return socket.sendJSON "tenpoints:tenpoint", {
        model: doc.toJSON()
      }

  sockrooms.on "tenpoints/fetch_tenpoint_list", (socket, session, data) ->
    tenpoints.fetch_tenpoint_list session, (err, docs) ->
      return sockrooms.handleError(socket, err) if err?
      for doc in docs.group
        doc.sharing = utils.clean_sharing(session, doc)
      for doc in docs.public
        doc.sharing = utils.clean_sharing(session, doc)
      return socket.sendJSON(data.callback or "tenpoints:list", {model: doc})

  sockrooms.on "tenpoints/save_tenpoint", (socket, session, data) ->
    tenpoints.save_tenpoint session, data, (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      orig_sharing = doc.sharing
      # Broadcast directly back, because if this is a new model, the sender
      # won't be in the room yet.
      doc.sharing = utils.clean_sharing(session, doc)
      socket.sendJSON "tenpoints:tenpoint", {model: doc}
      sockrooms.roomSocketSessionMap "tenpoints/#{doc.id}", (err, socket, sess) ->
        return logger.error(err) if err?
        if sess.session_id != session.session_id
          doc.sharing = utils.clean_sharing(sess, {sharing: orig_sharing})
          socket.sendJSON "tenpoints:tenpoint", {model: doc}

  sockrooms.on "tenpoints/revise_point", (socket, session, data) ->
    tenpoints.revise_point session, data, (err, doc, point, event, si) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast("tenpoints/#{doc.id}", "tenpoints:point", {
        _id: doc.id
        point: point
      })

  sockrooms.on "tenpoints/support_point", (socket, session, data) ->
    tenpoints.change_support session, data, (err, doc, point, event) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast("tenpoints/#{doc.id}", "tenpoints:support", {
        _id: doc.id
        point_id: data.point_id
        user_id: data.user_id
        name: data.name
        vote: data.vote
      })

  sockrooms.on "tenpoints/set_editing", (socket, session, data) ->
    tenpoints.set_editing session, data, (err, doc, point) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast("tenpoints/#{doc.id}", "tenpoints:editing", {
        _id: doc.id
        point_id: data.point_id
        editing: point.editing
      })

  sockrooms.on "tenpoints/check_slug", (socket, session, data) ->
    schema.TenPoint.findOne {slug: data.slug}, '_id', (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      socket.sendJSON(data.callback or "tenpoints:check_slug", {ok: not doc?})

module.exports = {start}
