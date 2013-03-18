_             = require 'underscore'
async         = require 'async'
utils         = require '../../../lib/utils'
logger        = require('log4js').getLogger("resolve")

start = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  api_methods = require("../../../lib/api_methods")(config)
  www_methods = require("../../../lib/www_methods")(config)
  resolve = require("./resolve")(config)
  sockrooms.addChannelAuth "resolve", (session, room, callback) ->
    name = room.split("/")[1]
    schema.Proposal.findOne {_id: name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      return callback("Proposal #{name} not found") unless doc?
      return callback(null, utils.can_view(session, doc))
  
  #
  # Routes
  #

  server_error = (req, res, err) ->
    www_methods.handle_error(req, res, err)

  not_found = (req, res) ->
    www_methods.not_found(req, res)

  bad_request = (req, res, err) ->
    www_methods.bad_request(req, res, err)

  permission_denied = (req, res) ->
    www_methods.permission_denied(req, res)

  context = (req, obj, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "resolve"},
        utils.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: utils.clean_conf(config)
      flash: req.flash()
    }, obj)

  index_res = (req, res, extra_context, initial_data) ->
    utils.list_accessible_documents schema.Proposal, req.session, (err, docs) ->
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

  utils.append_slash(app, "/resolve/p/([^/]+)")
  app.get "/resolve/p/:id/", (req, res) ->
    schema.Proposal.findOne {_id: req.params.id}, (err, doc) ->
      return server_error(req, res, err) if err?
      return not_found(req, res) unless doc?
      return permission_denied(req, res) unless utils.can_view(req.session, doc)
      index_res(req, res, {
        title: "Resolve: " + doc.title
      }, {
        proposal: doc
      })
      resolve.post_event(
        req.session, doc, "visit", {timeout: 60 * 5000}
      )

  sockrooms.on "resolve/post_twinkle", (socket, session, data) ->
    respond = (err, twinkle, proposal) ->
      return socket.sendJSON "error", {error: err} if err?
      sockrooms.broadcast(
        "resolve/" + proposal.id,
        "twinkles",
        { twinkles: [twinkle] })

    return respond("Missing entity") unless data.entity?
    return respond("Missing subentity") unless data.subentity?
    resolve.post_twinkle(session, data.entity, data.subentity, respond)

  sockrooms.on "resolve/remove_twinkle", (socket, session, data) ->
    respond = (err, twinkle, proposal) ->
      return socket.sendJSON "error", {error: err} if err?
      sockrooms.broadcast(
        "resolve/" + proposal.id,
        "twinkles",
        {remove: data.twinkle_id}
      )

    return respond("Missing twinkle_id") unless data.twinkle_id?
    return respond("Missing entity") unless data.entity?
    resolve.remove_twinkle(session, data.twinkle_id, data.entity, respond)

  sockrooms.on "resolve/get_twinkles", (socket, session, data) ->
    async.waterfall [
      (done) ->
        return done("Missing entity") unless data.entity?
        schema.Proposal.findOne {_id: data.entity}, (err, doc) ->
          return done(err) if err?
          unless utils.can_view(session, doc)
            return done("Permission denied")
          api_methods.get_twinkles {
            application: "resolve"
            entity: doc._id
          }, done

    ], (err, twinkles) ->
      return socket.sendJSON "error", {error: err} if err?
      socket.sendJSON "twinkles", {twinkles: twinkles}

  sockrooms.on "resolve/get_proposal_list", (socket, session, data) ->
    if not data?.callback?
      socket.sendJSON "error", {error: "Missing callback parameter."}
    else
      utils.list_accessible_documents(
        schema.Proposal, session, (err, proposals) ->
          if err? then return socket.sendJSON data.callback, {error: err}
          socket.sendJSON data.callback, {proposals}
      )

  sockrooms.on "resolve/get_proposal", (socket, session, data) ->
    unless data.callback?
      return socket.sendJSON "error", {error: "Missing 'callback' parameter"}
    schema.Proposal.findOne data.proposal, (err, proposal) ->
      response = {}
      unless utils.can_view(session, proposal)
        response.error = "Permission denied"
      else
        proposal.sharing = utils.clean_sharing(session, proposal)
        response.proposal = proposal
      socket.sendJSON data.callback, response
      resolve.post_event(
        session, proposal, "visit", {timeout: 60 * 5000}
      )

  sockrooms.on "resolve/get_proposal_events", (socket, session, data) ->
    respond = (err, events) ->
      return socket.sendJSON "error", {error: err} if err?
      return socket.sendJSON data.callback, {events: events}

    return respond("Missing proposal ID") unless data.proposal_id?
    return respond("Missing callback") unless data.callback?
    schema.Proposal.findOne {_id: data.proposal_id}, (err, doc) ->
      unless utils.can_view(session, doc)
        return respond("Permission denied")
      api_methods.get_events {
        application: "resolve"
        entity: doc._id
      }, respond

  sockrooms.on "resolve/save_proposal", (socket, session, data) ->
    respond = (err, proposal) ->
      if err?
        return socket.sendJSON data.callback, {error: err} if data.callback?
        return socket.sendJSON "error", {error: err}
      sockrooms.broadcast(
        "resolve/" + proposal.id,
        "proposal_change",
        {proposal},
        socket.sid)
      socket.sendJSON(data.callback, {proposal}) if data.callback?

    broadcast_notices = (err, proposal, events, search_indices, notices) ->
      if err?
        return socket.sendJSON data.callback, {error: err} if data.callback?
        return socket.sendJSON "error", {error: err}
      user_id = session.auth?.user_id
      for notice in notices
        payload = {notification: [notice]}
        sockrooms.broadcast(
          notice.recipient.toString(),
          "notifications",
          payload)

    if data.opinion? and not data.proposal?
      return respond("Missing {proposal: {_id: ..}}")
    
    # Fetch the proposal.
    switch data.action
      when "create"
        resolve.create_proposal(session, data, respond, broadcast_notices)
      when "update"
        resolve.update_proposal(session, data, respond, broadcast_notices)
      when "append"
        resolve.add_opinion(session, data, respond, broadcast_notices)
      when "trim"
        resolve.remove_opinion(session, data, respond, broadcast_notices)


module.exports = {start}
