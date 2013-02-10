express       = require 'express'
socketio      = require 'socket.io'
intertwinkles = require '../../../lib/intertwinkles'
RoomManager   = require('iorooms').RoomManager
RedisStore    = require('connect-redis')(express)
_             = require 'underscore'
async         = require 'async'
mongoose      = require 'mongoose'
logger        = require('log4js').getLogger()

start = (config, app, io, sessionStore) ->
  schema = require('./schema').load(config)
  api_methods = require("../../../lib/api_methods")(config)
  iorooms = new RoomManager("/io-resolve", io, sessionStore)
  
  #
  # Routes
  #

  server_error = (req, res, err) ->
    res.statusCode = 500
    logger.error(err)
    return res.send("Server error") # TODO pretty 500 page

  not_found = (req, res) ->
    res.statusCode = 404
    return res.send("Not found") # TODO pretty 404 page

  bad_request = (req, res) ->
    res.statusCode = 400
    return res.send("Bad request") # TODO pretty 400 page

  permission_denied = (req, res) ->
    res.statusCode = 403
    return res.send("Permission denied") # TODO pretty 403, or redirect to login

  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "resolve"},
        intertwinkles.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: intertwinkles.clean_conf(config)
      flash: req.flash()
    }, obj)

  index_res = (req, res, extra_context, initial_data) ->
    intertwinkles.list_accessible_documents schema.Proposal, req.session, (err, docs) ->
      return server_error(req, res, err) if err?
      res.render 'resolve/index', context(req, extra_context or {}, _.extend(initial_data or {}, {
        listed_proposals: docs
      }))

  app.get /\/resolve$/, (req, res) -> res.redirect('/resolve/')
  app.get "/resolve/", (req, res) ->
    index_res(req, res, {
      title: "Resolve: Decide Something"
    })

  app.get "/resolve/new/", (req, res) ->
    index_res(req, res, {
      title: "New proposal"
    })

  app.get "/resolve/p/:id/", (req, res) ->
    schema.Proposal.findOne {_id: req.params.id}, (err, doc) ->
      return server_error(req, res, err) if err?
      return not_found(req, res) unless doc?
      return permission_denied(req, res) unless intertwinkles.can_view(req.session, doc)
      index_res(req, res, {
        title: "Resolve: " + doc.title
      }, {
        proposal: doc
      })
      resolve.post_event(
        req.session, doc, "visit", {timeout: 60 * 5000}
      )

  iorooms.onChannel "post_twinkle", (socket, data) ->
    respond = (err, twinkle, proposal) ->
      return socket.emit "error", {error: err} if err?
      socket.broadcast.to(proposal.id).emit "twinkles", { twinkles: [twinkle] }
      socket.emit "twinkles", { twinkles: [twinkle] }

    return respond("Missing entity") unless data.entity?
    return respond("Missing subentity") unless data.subentity?
    resolve.post_twinkle(socket.session, data.entity, data.subentity, respond)

  iorooms.onChannel "remove_twinkle", (socket, data) ->
    respond = (err, twinkle, proposal) ->
      return socket.emit "error", {error: err} if err?
      socket.broadcast.to(proposal.id).emit "twinkles", {remove: data.twinkle_id}
      socket.emit "twinkles", {remove: data.twinkle_id}

    return respond("Missing twinkle_id") unless data.twinkle_id?
    return respond("Missing entity") unless data.entity?
    resolve.remove_twinkle(socket.session, data.twinkle_id, data.entity, respond)

  iorooms.onChannel "get_twinkles", (socket, data) ->
    async.waterfall [
      (done) ->
        return done("Missing entity") unless data.entity?
        schema.Proposal.findOne {_id: data.entity}, (err, doc) ->
          return done(err) if err?
          unless intertwinkles.can_view(socket.session, doc)
            return done("Permission denied")
          api_methods.get_twinkles {
            application: "resolve"
            entity: doc._id
          }, done

    ], (err, twinkles) ->
      return socket.emit "error", {error: err} if err?
      socket.emit "twinkles", {twinkles: twinkles}

  iorooms.onChannel "get_proposal_list", (socket, data) ->
    if not data?.callback?
      socket.emit "error", {error: "Missing callback parameter."}
    else
      intertwinkles.list_accessible_documents(
        schema.Proposal, socket.session, (err, proposals) ->
          if err? then return socket.emit data.callback, {error: err}
          socket.emit data.callback, {proposals}
      )

  iorooms.onChannel "get_proposal", (socket, data) ->
    unless data.callback?
      return socket.emit "error", {error: "Missing 'callback' parameter"}
    schema.Proposal.findOne data.proposal, (err, proposal) ->
      response = {}
      unless intertwinkles.can_view(socket.session, proposal)
        response.error = "Permission denied"
      else
        proposal.sharing = intertwinkles.clean_sharing(socket.session, proposal)
        response.proposal = proposal
      socket.emit data.callback, response
      resolve.post_event(
        socket.session, proposal, "visit", {timeout: 60 * 5000}
      )

  iorooms.onChannel "get_proposal_events", (socket, data) ->
    respond = (err, events) ->
      return socket.emit "error", {error: err} if err?
      return socket.emit data.callback, {evvents: events}

    return respond("Missing proposal ID") unless data.proposal_id?
    return respond("Missing callback") unless data.callback?
    schema.Proposal.findOne {_id: data.proposal_id}, (err, doc) ->
      unless intertwinkles.can_view(socket.session, doc)
        return respond("Permission denied")
      api_methods.get_events {
        application: "resolve"
        entity: doc._id
      }, respond

  iorooms.onChannel "save_proposal", (socket, data) ->
    respond = (err, proposal) ->
      if err?
        return socket.emit data.callback, {error: err} if data.callback?
        return socket.emit "error", {error: err}
      socket.broadcast.to(proposal._id).emit "proposal_change", {proposal }
      socket.emit(data.callback, {proposal}) if data.callback?

    broadcast_notices = (err, proposal, events, search_indices, notices) ->
      if err?
        return socket.emit data.callback, {error: err} if data.callback?
        return socket.emit "error", {error: err}
      user_id = socket.session.auth?.user_id
      for notice in notices
        payload = {notification: [notice]}
        socket.broadcast.to(notice.recipient.toString()).emit "notifications", payload
        if user_id == notice.recipient.toString()
          socket.emit "notifications", payload

    if data.opinion? and not data.proposal?
      return respond("Missing {proposal: {_id: ..}}")
    
    # Fetch the proposal.
    switch data.action
      when "create"
        resolve.create_proposal(socket.session, data, respond, broadcast_notices)
      when "update"
        resolve.update_proposal(socket.session, data, respond, broadcast_notices)
      when "append"
        resolve.add_opinion(socket.session, data, respond, broadcast_notices)
      when "trim"
        resolve.remove_opinion(socket.session, data, respond, broadcast_notices)


module.exports = {start}
