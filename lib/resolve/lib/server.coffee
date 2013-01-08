express       = require 'express'
socketio      = require 'socket.io'
intertwinkles = require 'node-intertwinkles'
RoomManager   = require('iorooms').RoomManager
RedisStore    = require('connect-redis')(express)
_             = require 'underscore'
async         = require 'async'
mongoose      = require 'mongoose'

start = (config, app, io, sessionStore) ->
  schema = require('./schema').load(config)
  iorooms = new RoomManager("/io-resolve", io, sessionStore)
  
  #
  # Routes
  #

  server_error = (req, res, err) ->
    res.statusCode = 500
    console.error(err)
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

  resolve_post_event = (session, path, doc, type, opts) ->
    event = _.extend {
        application: "resolve"
        type: type
        entity_url: path
        entity: doc._id
        user: session.auth?.user_id
        via_user: session.auth?.user_id
        anon_id: session.anon_id
        group: doc.sharing.group_id
        data: {
          title: doc.title
          action: opts.data
        }
      }, opts.overrides or {}
    intertwinkles.post_event(event, config, opts.callback or (->), opts.timeout)

  resolve_post_search_index = (doc) ->
    votes_expanded = {
      yes: "Strongly approve"
      weak_yes: "Approve with reservations"
      discuss: "Need more discussion"
      no: "Have concerns"
      block: "Block"
      abstain: "I have a conflict of interest"
    }
    parts = [doc.revisions[0].text, "by #{doc.revisions[0].name}"]
    parts = parts.concat([
          o.name + ":", o.revisions[0].text, votes_expanded[o.revisions[0].vote]
      ].join(" ") for o in doc.opinions)
    if doc.resolved?
      if doc.passed then parts.push("Passed") else parts.push("Failed")

    search_data = {
      application: "resolve"
      entity: doc._id
      type: "proposal"
      url: "/resolve/p/#{doc._id}/"
      title: doc.title
      summary: "Proposal with #{doc.opinions.length} responses."
      text: parts.join("\n")
      sharing: doc.sharing
    }
    intertwinkles.post_search_index(search_data, config)


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
      resolve_post_event(
        req.session, req.originalUrl, doc, "visit", {timeout: 60 * 5000}
      )

  iorooms.onChannel "post_twinkle", (socket, data) ->
    async.waterfall [
      (done) ->
        params = data.twinkle
        for key in ["entity", "subentity"]
          return done("Missing #{key}") unless data[key]?

        schema.Proposal.findOne {_id: data.entity}, (err, doc) ->
          return done(err) if err?
          return done("Not found") unless doc?
          unless intertwinkles.can_view(socket.session, doc)
            return done("Permission denied")

          recipient_id = null
          revision = _.find doc.revisions, (r) -> r._id.toString() == data.subentity
          if revision
            recipient_id = revision.user_id
          else
            opinion = _.find doc.opinions, (o) ->
              for rev in o.revisions
                return true if rev._id.toString() == data.subentity
              return false
            if opinion
              recipient_id = opinion.user_id
            else
              return done("Unknown subentity")
          return done(null, doc, recipient_id)

      (doc, recipient_id, done) ->
        intertwinkles.post_twinkle {
          application: "resolve"
          entity: doc._id
          subentity: data.subentity
          url: "/resolve/p/#{doc._id}/"
          sender: socket.session.auth?.user_id
          sender_anon_id: socket.session.anon_id
          recipient: recipient_id
        }, config, (err, results) ->
          done(err, results, doc)

    ], (err, results, doc) ->
      return socket.emit "error", {error: err} if err?
      socket.broadcast.to(doc.id).emit "twinkles", { twinkles: [results.twinkle] }
      socket.emit "twinkles", { twinkles: [results.twinkle] }

  iorooms.onChannel "remove_twinkle", (socket, data) ->
    async.waterfall [
      (done) ->
        return done("Missing twinkle_id") unless data.twinkle_id?
        return done("Missing entity") unless data.entity?
        schema.Proposal.findOne {_id: data.entity}, 'sharing', (err, doc) ->
          unless intertwinkles.can_view(socket.session, doc)
            return done("Permission denied")

          intertwinkles.remove_twinkle {
            twinkle_id: data.twinkle_id
            entity: data.entity
            sender: socket.session.auth?.user_id or null
            sender_anon_id: socket.session.anon_id
          }, config, (err, results) ->
            return done(err, results, doc)
    ], (err, results, doc) ->
      return socket.emit "error", {error: err} if err?
      socket.broadcast.to(doc.id).emit "twinkles", {remove: data.twinkle_id}
      socket.emit "twinkles", {remove: data.twinkle_id}

  iorooms.onChannel "get_twinkles", (socket, data) ->
    async.waterfall [
      (done) ->
        return done("Missing entity") unless data.entity?
        schema.Proposal.findOne {_id: data.entity}, (err, doc) ->
          return done(err) if err?
          unless intertwinkles.can_view(socket.session, doc)
            return done("Permission denied")
          intertwinkles.get_twinkles {
            application: "resolve"
            entity: doc._id
          }, config, done

    ], (err, twinkles) ->
      return socket.emit "error", {error: err} if err?
      socket.emit "twinkles", twinkles

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
      resolve_post_event(
        socket.session, "/resolve/p/#{proposal._id}", proposal, "visit", {timeout: 60 * 5000}
      )

  iorooms.onChannel "get_proposal_events", (socket, data) ->
    unless data.proposal_id?
      return socket.emit "error", {error: "Missing proposal ID"}
    unless data.callback?
      return socket.emit "error", {error: "Missing callback"}
    schema.Proposal.findOne {_id: data.proposal_id}, (err, doc) ->
      if not intertwinkles.can_view(socket.session, doc)
        return socket.emit "error", {error: "Permission denied"}
      intertwinkles.get_events {
        application: "resolve"
        entity: doc._id
      }, config, (err, results) ->
        return socket.emit "error", {error: err} if err?
        socket.emit data.callback, {events: results?.events}

  iorooms.onChannel "save_proposal", (socket, data) ->
    if data.opinion? and not data.proposal?
      return socket.emit data.callback or "error", {error: "Missing {proposal: _id}"}

    # Data we'll use to log events ("create", "update", "append", etc) for
    # later visualization.
    event_data = {data: {}}

    async.waterfall [
      # Fetch the proposal.
      (done) ->
        if data.proposal._id?
          schema.Proposal.findOne {_id: data.proposal._id}, (err, proposal) ->
            return done(err) if err?
            if intertwinkles.can_edit(socket.session, proposal)
              done(null, proposal)
            else
              done("Permission denied.")
        else
          done(null, new schema.Proposal())

      # Update and save it. 
      (proposal, done) ->
        switch data.action

          # Change the proposal.
          when "create", "update"
            return done("Missing proposal data.") unless data.proposal?

            # Update sharing.
            if data.proposal?.sharing?
              unless intertwinkles.can_change_sharing(socket.session, proposal)
                return done("Not allowed to change sharing.")
              if (data.proposal.sharing.group_id? and
                  not socket.session.groups[data.proposal.sharing.group_id]?)
                return done("Unauthorized group")
              proposal.sharing = data.proposal.sharing
              event_data.data.sharing = intertwinkles.clean_sharing({}, proposal)

            # Add a revision.
            if data.proposal?.proposal?
              if intertwinkles.is_authenticated(socket.session)
                name = socket.session.users[socket.session.auth.user_id].name
              else
                name = data.proposal.name
              unless name?
                return done("Missing name for proposal revision.")
              proposal.revisions.unshift({
                user_id: socket.session.auth?.user_id
                name: name
                text: data.proposal.proposal
              })
              event_data.data.proposal = proposal.revisions[0]
            if proposal.revisions.length == 0
              return done("Missing proposal field.")

            # Finalize the proposal.
            if data.proposal?.passed?
              proposal.passed = data.proposal.passed
              proposal.resolved = new Date()
              event_data.data.passed = data.proposal.passed
            else if data.proposal?.reopened?
              proposal.passed = null
              proposal.resolved = null
              event_data.data.reopened = true

            proposal.save(done)

          # Add a vote.
          when "append"
            return done("Missing opinion text") unless data.opinion?.text
            return done("Missing vote") unless data.opinion?.vote
            if data.opinion?.user_id
              user_id = data.opinion.user_id
              user = socket.session.users[user_id]
              return done("Unauthorized user id") unless user?
              name = user.name
            else
              user_id = null
              name = data.opinion.name
            event_data.user = user_id
            event_data.data.name = name

            if user_id?
              opinion_set = _.find proposal.opinions, (o) ->
                o.user_id == user_id
            else
              opinion_set = _.find proposal.opinions, (o) ->
                (not o.user_id?) and o.name == name
            if not opinion_set
              opinion_set = {
                user_id: user_id
                name: name
                revisions: [{
                  text: data.opinion.text
                  vote: data.opinion.vote
                }]
              }
              proposal.opinions.push(opinion_set)
            else
              if (opinion_set.revisions.length > 0 and
                  opinion_set.revisions[0].text == data.opinion.text and
                  opinion_set.revisions[0].vote == data.opinion.vote)
                opinion_set.revisions[0].date = new Date()
              else
                opinion_set.revisions.unshift({
                  text: data.opinion.text
                  vote: data.opinion.vote
                })
            event_data.data.opinion = {
              user_id: opinion_set.user_id
              name: opinion_set.name
              text: data.opinion.text
              vote: data.opinion.vote
            }
            proposal.save (err, doc) ->
              return done(err, doc)

          # Delete a vote.
          when "trim"
            return done("Missing opinion id") unless data.opinion?._id
            found = false
            for opinion, i in proposal.opinions
              if opinion._id.toString() == data.opinion._id
                event_data.data.deleted_opinion = proposal.opinions.splice(i, 1)[0]
                found = true
                break
            unless found
              return done("Opinion for `#{data.opinion._id}` not found.")
            proposal.save (err, doc) ->
              return done(err, doc)

    ], (err, proposal) ->
      if err?
        if data.callback?
          return socket.emit data.callback, {error: err}
        else
          return socket.emit "error", {error: err}

      # Emit the result.
      emittal = { proposal: proposal }
      socket.broadcast.to(proposal._id).emit "proposal_change", emittal
      socket.emit(data.callback, emittal) if data.callback?

      # Log events
      resolve_post_event(
        socket.session, "/resolve/p/#{proposal.id}/", proposal, data.action, event_data
      )
      # Post search index
      resolve_post_search_index(proposal)
      # XXX: This is an inefficient but easy strategy for syncing notifications
      # -- one database insert for each group member for every write to this
      # doc, as well as a wider removal. Could do better by more intelligently
      # figuring out who needs their notification changed.
      #
      # Update notifications.
      # 1. remove all notifications associated with this entity.
      intertwinkles.clear_notices {
        application: "resolve",
        type: "proposal"
        entity: proposal._id
      }, config, (err, results) ->
        return console.error(err) if err?

        intertwinkles.broadcast_notices(socket, results.notifications)

        # 2. Now post new notifications for all people that need them.
        if proposal.sharing.group_id and not proposal.resolved?
          group = socket.session.groups[proposal.sharing.group_id]
          member_ids = (m.user for m in group.members)
          current_voters = []
          stale_voters = []
          cutoff = proposal.revisions[0].date
          for opinion in proposal.opinions
            if opinion.user_id?
              if opinion.revisions[0].date > cutoff
                current_voters.push(opinion.user_id)
              else
                stale_voters.push(opinion.user_id)
          needed = _.difference(member_ids, current_voters)
          notices = []
          for user_id in needed
            if _.contains stale_voters, user_id
              web = """
                A proposal from #{group.name} has changed since you voted.
                Please confirm your vote.
              """
            else
              web = """#{group.name} needs your response to a proposal! """
            notices.push({
              application: "resolve"
              type: "proposal"
              entity: proposal._id
              group: proposal.sharing.group_id
              recipient: user_id
              url: "/resolve/p/#{proposal._id}/"
              sender: proposal.revisions[0].user_id
              formats: { web }
            })
          if notices.length > 0
            intertwinkles.post_notices notices, config, (err, results) ->
              return console.error err if err?
              intertwinkles.broadcast_notices(socket, results.notifications)

module.exports = {start}
