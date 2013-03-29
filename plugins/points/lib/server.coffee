_             = require 'underscore'
utils         = require '../../../lib/utils'

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  www_methods = require("../../../lib/www_methods")(config)
  pointslib = require("./pointslib")(config)

  sockrooms.addChannelAuth "points", (session, room, callback) ->
    name = room.split("/")[1]
    schema.PointSet.findOne {_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      return callback("PointSet #{name} not found") unless doc?
      return callback(null, utils.can_view(session, doc))

  index_res = (req, res, initial_data={}) ->
    utils.list_accessible_documents schema.PointSet, req.session, (err, docs) ->
      return www_methods.handle_error(req, res, err) if err?
      for doc in docs.group
        doc.sharing = utils.clean_sharing(req.session, doc)
      for doc in docs.public
        doc.sharing = utils.clean_sharing(req.session, doc)
      res.render 'points/index', {
        title: "Points of Unity"
        initial_data: _.extend(
          {application: "points", pointsets_list: docs},
          utils.get_initial_data(req.session, config),
          initial_data
        )
        conf: utils.clean_conf(config)
        flash: req.flash()
      }

  #
  # Routes
  #

  utils.append_slash(app, "/points")
  app.get '/points/', (req, res) -> index_res(req, res)

  utils.append_slash(app, "/points/add")
  app.get '/points/add/', (req, res) -> index_res(req, res)

  utils.append_slash(app, "/points/u/.*[^/]$")
  app.get '/points/u/:slug/:tag?/:id?/', (req, res) ->
    schema.PointSet.findOne {slug: req.params.slug}, (err, doc) ->
      return www_methods.handle_error(req, res, err) if err?
      return www_methods.not_found(req, res) unless doc?
      unless utils.can_view(req.session, doc)
        if utils.is_authenticated(req.session)
          return www_methods.permission_denied(req, res)
        else
          return www_methods.redirect_to_login(req, res)

      pointslib.post_event(req.session, doc, {type: "visit"}, 5 * 1000 * 60,
        (err, timeout) ->
          doc.sharing = utils.clean_sharing(req.session, doc)
          index_res(req, res, { pointset: doc.toJSON() })
      )

  #
  # Socket routes
  #

  sockrooms.on "points/fetch_pointset", (socket, session, data) ->
    pointslib.fetch_pointset data.slug, session, (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      doc.sharing = utils.clean_sharing(session, doc)
      return socket.sendJSON "points:pointset", {
        model: doc.toJSON()
      }

  sockrooms.on "points/fetch_pointset_list", (socket, session, data) ->
    pointslib.fetch_pointset_list session, (err, docs) ->
      return sockrooms.handleError(socket, err) if err?
      for doc in docs.group
        doc.sharing = utils.clean_sharing(session, doc)
      for doc in docs.public
        doc.sharing = utils.clean_sharing(session, doc)
      return socket.sendJSON(data.callback or "points:list", {model: doc})

  sockrooms.on "points/save_pointset", (socket, session, data) ->
    pointslib.save_pointset session, data, (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      orig_sharing = doc.sharing
      # Broadcast directly back, because if this is a new model, the sender
      # won't be in the room yet.
      doc.sharing = utils.clean_sharing(session, doc)
      socket.sendJSON "points:pointset", {model: doc}
      sockrooms.roomSocketSessionMap "points/#{doc.id}", (err, socket, sess) ->
        return logger.error(err) if err?
        if sess.session_id != session.session_id
          doc.sharing = utils.clean_sharing(sess, {sharing: orig_sharing})
          socket.sendJSON "points:pointset", {model: doc}

  sockrooms.on "points/revise_point", (socket, session, data) ->
    pointslib.revise_point session, data, (err, doc, point, event, si) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast("points/#{doc.id}", "points:point", {
        _id: doc.id
        point: point
      })

  sockrooms.on "points/support_point", (socket, session, data) ->
    pointslib.change_support session, data, (err, doc, point, event) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast("points/#{doc.id}", "points:support", {
        _id: doc.id
        point_id: point._id
        user_id: data.user_id
        name: data.name
        vote: data.vote
      })

  sockrooms.on "points/set_editing", (socket, session, data) ->
    pointslib.set_editing session, data, (err, doc, point) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast("points/#{doc.id}", "points:editing", {
        _id: doc.id
        point_id: point._id
        editing: point.editing
      })

  sockrooms.on "points/set_approved", (socket, session, data) ->
    pointslib.set_approved session, data, (err, doc, point) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast("points/#{doc.id}", "points:approved", {
        _id: doc.id
        point_id: point._id
        approved: doc.is_approved(point)
      })

  sockrooms.on "points/move_point", (socket, session, data) ->
    pointslib.move_point session, data, (err, doc, point) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.broadcast("points/#{doc.id}", "points:move", {
        _id: doc.id
        point_id: point._id
        position: data.position
      })

  sockrooms.on "points/check_slug", (socket, session, data) ->
    schema.PointSet.findOne {slug: data.slug}, '_id', (err, doc) ->
      return sockrooms.handleError(socket, err) if err?
      socket.sendJSON(data.callback or "points:check_slug", {ok: not doc?})

  sockrooms.on "leave", (data) ->
    #
    # Clear any active editing when a socket disconnects.
    #
    {socket, session, room, last} = data
    [channel, _id] = room.split('/')
    if channel == "points"
      schema.PointSet.findOne {_id}, (err, doc) ->
        return sockrooms.handleError(socket, err) if err?
        return unless doc?
        emissions = []
        for list in [doc.points, doc.drafts]
          for point in list
            if _.contains(point.editing, session.anon_id)
              point.editing = _.without(point.editing, session.anon_id)
              emissions.push {
                _id: doc._id
                point_id: point._id
                editing: point.editing
              }
        return unless emissions.length > 0
        doc.save (err, doc) ->
          if err? then sockrooms.handleError(socket, err)
          for emission in emissions
            sockrooms.broadcast(room, "points:editing", emission)

  sockrooms.on "points/get_points_events", (socket, session, data) ->
    pointslib.get_events session, data, (err, events) ->
      return sockrooms.handleError(socket, err) if err?
      socket.sendJSON("points:events", {_id: data._id, events: events})

module.exports = {start}
