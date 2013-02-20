utils         = require '../../../lib/utils'
_             = require 'underscore'
async         = require 'async'
logger        = require('log4js').getLogger()

module.exports = (config) ->
  schema = require('./schema').load(config)
  api_methods = require("../../../lib/api_methods")(config)

  r = {} # Return object
  #
  # Post an event for the given proposal.
  #
  r.post_event = (session, proposal, type, opts) ->
    event = _.extend {
        application: "resolve"
        type: type
        entity_url: "/resolve/p/#{proposal.id}/"
        entity: proposal._id
        user: session.auth?.user_id
        via_user: session.auth?.user_id
        anon_id: session.anon_id
        group: proposal.sharing.group_id
        data: {
          title: proposal.title
          action: opts.data
        }
      }, opts.overrides or {}
    api_methods.post_event(event, opts.timeout or 0, opts.callback or (->))

  #
  # Post a search index for the given proposal
  #
  r.post_search_index = (proposal, callback) ->
    doc = proposal
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
      entity: doc.id
      type: "proposal"
      url: "/resolve/p/#{doc._id}/"
      title: doc.title
      summary: "Proposal with #{doc.opinions.length} responses."
      text: parts.join("\n")
      sharing: doc.sharing
    }
    api_methods.add_search_index(search_data, callback)

  #
  # Add a twinkle for a proposal with given proposal ID, and subentity
  # referring to either an opinion or proposal revision.
  #
  # callback(err, twinkle, proposal)
  #
  r.post_twinkle = (session, proposal_id, subentity, callback) ->
    async.waterfall [
      (done) ->
        schema.Proposal.findOne {_id: proposal_id}, (err, doc) ->
          return done(err) if err?
          return done("Not found") unless doc?
          unless utils.can_view(session, doc)
            return done("Permission denied")

          recipient_id = null
          revision = _.find doc.revisions, (r) -> r._id.toString() == subentity.toString()
          if revision
            recipient_id = revision.user_id
          else
            opinion = _.find doc.opinions, (o) ->
              for rev in o.revisions
                return true if rev._id.toString() == subentity.toString()
              return false
            if opinion
              recipient_id = opinion.user_id
            else
              return done("Unknown subentity")
          return done(null, doc, recipient_id)

      (doc, recipient_id, done) ->
        api_methods.post_twinkle {
          application: "resolve"
          entity: doc._id
          subentity: subentity
          url: "/resolve/p/#{doc._id}/"
          sender: session.auth?.user_id
          sender_anon_id: session.anon_id
          recipient: recipient_id
        }, (err, results) ->
          done(err, results, doc)

    ], (err, twinkle, doc) ->
      callback(err, twinkle, doc)

  #
  # Update notifications for a proposal
  #
  r.update_notifications = (session, proposal, callback=(->)) ->
    # XXX: This is an inefficient but easy strategy for syncing notifications
    # -- one database insert for each group member for every write to this
    # doc, as well as a wider removal. Could do better by more intelligently
    # figuring out who needs their notification changed.

    # This will contain both 'clear' updates and new notices.
    notices_to_broadcast = []
    notice_type = "needs_my_response"
    
    # 1. remove all notifications associated with this entity.
    api_methods.clear_notifications {
      application: "resolve",
      type: notice_type
      entity: proposal.id
    }, (err, notifications) ->
      if err?
        callback?(err)
        return logger.error(err)

      # Append the 'cleared' notices to our broadcast.
      notices_to_broadcast = notices_to_broadcast.concat(notifications)

      # 2. Now post new notifications for all people that still need them.
      if proposal.sharing.group_id and not proposal.resolved?
        group = session.groups[proposal.sharing.group_id]
        member_ids = (m.user.toString() for m in group.members)
        current_voters = []
        stale_voters = []
        cutoff = proposal.revisions[0].date
        for opinion in proposal.opinions
          if opinion.user_id?
            if opinion.revisions[0].date >= cutoff
              current_voters.push(opinion.user_id.toString())
            else
              stale_voters.push(opinion.user_id.toString())
        needed = _.difference(member_ids, current_voters)
        notices = []
        for user_id in needed
          #XXX Put these in templates.
          if _.contains stale_voters, user_id
            web = """
              A proposal from #{group.name} has changed since you voted.
              Please confirm your vote.
            """
          else
            web = """#{group.name} needs your response to a proposal! """
          notices.push({
            application: "resolve"
            type: notice_type
            entity: proposal._id.toString()
            recipient: user_id
            url: "/resolve/p/#{proposal._id}/"
            sender: proposal.revisions[0].user_id
            formats: { web }
          })
        if notices.length > 0
          return api_methods.post_notifications notices, (err, notifications) ->
            if err?
              logger.error err
              return callback(err)
            notices_to_broadcast = notices_to_broadcast.concat(notifications)
            return callback(null, notices_to_broadcast)
      return callback(null, notices_to_broadcast)

  #
  # Remove the twinkle specified by given:
  # { 
  #   "twinkle_id": "ObjectID string"
  #   "entity": "ObjectID string"
  # }
  #
  # callback(err, twinkle, proposal)
  #
  r.remove_twinkle = (session, twinkle_id, proposal_id, callback) ->
    async.waterfall [
      (done) ->
        return done("Missing twinkle_id") unless twinkle_id?
        return done("Missing proposal_id") unless proposal_id?
        schema.Proposal.findOne {_id: proposal_id}, 'sharing', (err, doc) ->
          unless utils.can_view(session, doc)
            return done("Permission denied")

          api_methods.delete_twinkle {
            twinkle_id: twinkle_id
            entity: proposal_id
            sender: session.auth?.user_id or null
            sender_anon_id: session.anon_id
          }, (err, results) ->
            return done(err, results, doc)
    ], (err, twinkles, doc) ->
      callback(err, twinkles, doc)

  #
  # Update proposals -- create, update, append, trim.
  #
  # data: {
  #   "proposal":{
  #       _id,
  #       ... other proposal options ...
  #   }
  #   "opinion": { ... opinion options, if any ... }
  # }
  #
  # Two different callbacks -- use one or both:
  #  - post_save_callback(err, proposal)
  #         fired after the doc is saved, but before events /
  #         search indices are updated.
  #  - post_events_callback(err, proposal, events, search_indices, notices)
  #         fired after everything is done.
  #
  #  On error, only the first non-null callback is fired.
  #

  #
  # Create
  #
  r.create_proposal = (session, data, post_save_callback, post_events_callback) ->
    proposal = new schema.Proposal()
    _update_proposal(session, proposal, data, "create",
      post_save_callback, post_events_callback)

  #
  # Update
  #
  r.update_proposal = (session, data, post_save_callback, post_events_callback) ->
    schema.Proposal.findOne {_id: data.proposal?._id}, (err, proposal) ->
      return callback(err) if err?
      _update_proposal(session, proposal, data, "update", post_save_callback, post_events_callback)

  # Create and update
  _update_proposal = (session, proposal, data, action,
                      post_save_callback, post_events_callback) ->
    error_out = (err) ->
      (post_save_callback or post_events_callback)(err)

    unless utils.can_edit(session, proposal)
      return error_out("Permission denied.")

    event_data = {}
    # Update sharing
    if data.proposal?.sharing?
      unless utils.can_change_sharing(session, proposal)
        return error_out("Not allowed to change sharing.")
      if (data.proposal.sharing.group_id? and
          not session.groups[data.proposal.sharing.group_id]?)
        return error_out("Unauthorized group")
      proposal.sharing = data.proposal.sharing
      event_data.sharing = utils.clean_sharing({}, proposal)

    # Add a revision.
    if data.proposal?.proposal?
      if utils.is_authenticated(session)
        name = session.users[session.auth.user_id].name
      else
        name = data.proposal.name
      unless name?
        return error_out("Missing name for proposal revision.")
      proposal.revisions.unshift({
        user_id: session.auth?.user_id
        name: name
        text: data.proposal.proposal
      })
      event_data.proposal = proposal.revisions[0]

    # Finalize the proposal
    if data.proposal?.passed?
      proposal.passed = data.proposal.passed
      proposal.resolved = new Date()
      event_data.passed = data.proposal.passed
    else if data.proposal?.reopened?
      proposal.passed = null
      proposal.resolved = null
      event_data.reopened = true

    proposal.save (err, doc) ->
      if err?
        return error_out(err)
      post_save_callback?(null, doc)
      _send_proposal_events(session, doc, action, event_data,
                            post_events_callback)

  #
  # Append
  #
  r.add_opinion = (session, data, post_save_callback, post_events_callback) ->
    error_out = (err) ->
      (post_save_callback or post_events_callback)?(err)

    return error_out("Missing proposal id") unless data?.proposal?._id?
    schema.Proposal.findOne {_id: data.proposal._id}, (err, proposal) ->
      unless utils.can_edit(session, proposal)
        return error_out("Permission denied.")
      return error_out("Missing opinion text") unless data.opinion?.text
      return error_out("Missing vote") unless data.opinion?.vote

      event_data = {data: {}}
      if data.opinion?.user_id
        # Authenticated.  Verify that the given ID is in the session
        # user's network. #XXX: Narrow this to the proposal's group?
        user_id = data.opinion.user_id
        user = session.users?[user_id]
        return error_out("Unauthorized user id") unless user?
        name = user.name
        # find previous opinion by ID.
        opinion_set = _.find proposal.opinions, (o) ->
          o.user_id == user_id
      else
        # Anonymous opinion.
        user_id = null
        name = data.opinion.name
        opinion_set = _.find proposal.opinions, (o) ->
          (not o.user_id?) and o.name == name

      event_data.user = user_id
      event_data.data.name = name

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
        if err?
          return error_out(err)
        post_save_callback?(null, doc)
        _send_proposal_events(session, proposal, "append", event_data,
                              post_events_callback)

  #
  # Trim
  #
  r.remove_opinion = (session, data, post_save_callback, post_events_callback) ->
    error_out = (err) ->
      (post_save_callback or post_events_callback)(err)
    event_data = {data: {}}
    schema.Proposal.findOne {_id: data.proposal._id}, (err, proposal) ->
      unless utils.can_edit(session, proposal)
        return error_out("Permission denied.")
      found = false
      for opinion, i in proposal.opinions
        if opinion._id.toString() == data.opinion._id.toString()
          event_data.data.deleted_opinion = proposal.opinions.splice(i, 1)[0]
          found = true
          break
      unless found
        return done("Opinion for `#{data.opinion._id}` not found.")
      proposal.save (err, doc) ->
        if err?
          return error_out(err)
        post_save_callback(null, doc)
        _send_proposal_events(session, doc, "trim", event_data,
                              post_events_callback)

  _send_proposal_events = (session, proposal, action, event_data, callback) ->
    async.parallel [
      # Post events.
      (done) ->
        r.post_event(session, proposal, action, {
          data: event_data
          callback: done
        })

      # Post search index.
      (done) ->
        r.post_search_index(proposal, done)

      # Update notifications
      (done) ->
        r.update_notifications session, proposal, done

    ], (err, results) ->
      [event, searchindex, notices] = results
      callback?(err, proposal, event, searchindex, notices)
  return r

