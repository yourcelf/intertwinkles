utils         = require '../../../lib/utils'
_             = require 'underscore'
async         = require 'async'
logger        = require('log4js').getLogger()
new_proposal_email_view     = require("../emails/new_proposal")
proposal_changed_email_view = require("../emails/proposal_changed")

module.exports = (config) ->
  schema = require('./schema').load(config)
  api_methods = require("../../../lib/api_methods")(config)
  {render_notifications} = require("../../../lib/email_notices").load(config)

  r = {} # Return object
  #
  # Post an event for the given proposal.
  #
  r.post_event = (session, proposal, event_opts, timeout, callback) ->
    event_opts.data or= {}
    event_opts.data.entity_name ?= proposal.title
    api_methods.post_event(_.extend({
      application: "resolve"
      url: proposal.url
      entity: proposal._id
      user: session.auth?.user_id
      anon_id: session.anon_id
      group: proposal.sharing.group_id
    }, event_opts), timeout, callback)

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
      url: doc.url
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
          url: doc.url
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

    # This will contain both 'clear' updates and new notices.  The clear
    # updates are broadcast over the socket so that any connected clients'
    # notice menu gets cleared.
    notice_type = "needs_my_response"
    
    async.series [
      # 1. remove all notifications associated with this entity.
      (done) ->
          api_methods.clear_notifications {
            application: "resolve",
            type: notice_type
            entity: proposal.id
          }, (err, notifications) ->
            return done(err) if err?
            done(null, notifications or [])

      # 2. Now render new notifications for all people that still need them.
      (done) ->
        if ((not proposal.sharing.group_id) or
            (proposal.resolved?) or
            (not session.groups?[proposal.sharing.group_id]))
          return done(null, [])

        # Identify who needs notices, of what type -- either "stale", or "new".
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

        # Function to map a user_id to a notification.
        render_proposal_notice =  (user_id, cb) ->
          if _.contains(stale_voters, user_id)
            view = proposal_changed_email_view
          else
            view = new_proposal_email_view
          render_notifications view, {
            group: group
            sender: session.users[session.auth.user_id]
            recipient: session.users[user_id]
            url: proposal.absolute_url
            application: "resolve"
            proposal: proposal
          }, (err, rendered) ->
            return cb(err) if err?
            cb(null, {
              application: "resolve"
              type: notice_type
              entity: proposal.id
              recipient: user_id
              url: proposal.url
              sender: session.auth.user_id
              formats: rendered
            })
        # Render the notices for each needed recipient.
        async.map(needed, render_proposal_notice, done)

      ], (err, results) ->
        return callback(err) if err?
        [ clear_notices, new_notices ] = results
        return callback(null, clear_notices) if new_notices.length == 0
        # Save new notices.
        api_methods.post_notifications new_notices, (err, notifications) ->
          return callback(err) if err?
          return callback(null, clear_notices.concat(notifications))

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

  #
  # Create
  #
  r.create_proposal = (session, data, callback) ->
    proposal = new schema.Proposal()
    _update_proposal(session, proposal, data, "create", callback)

  #
  # Update
  #
  r.update_proposal = (session, data, callback) ->
    schema.Proposal.findOne {_id: data.proposal?._id}, (err, proposal) ->
      return callback(err) if err?
      _update_proposal(session, proposal, data, "update", callback)

  # Create and update
  _update_proposal = (session, proposal, data, action, callback) ->

    unless utils.can_edit(session, proposal)
      return callback("Permission denied.")

    event_opts = {data: {}, type: action}
    # Update sharing
    if data.proposal?.sharing?
      unless utils.can_change_sharing(session, proposal)
        return callback("Not allowed to change sharing.")
      utils.update_sharing(proposal, data.proposal.sharing)
      # Make sure they can still change sharing.
      unless utils.can_change_sharing(session, proposal)
        return callback("Permission denied")
      event_opts.data.sharing = utils.clean_sharing({}, proposal)

    # Add a revision.
    if data.proposal?.proposal?
      if utils.is_authenticated(session)
        name = session.users[session.auth.user_id].name
      else
        name = data.proposal.name
      unless name?
        return callback("Missing name for proposal revision.")
      proposal.revisions.unshift({
        user_id: session.auth?.user_id
        name: name
        text: data.proposal.proposal
      })
      event_opts.data.revision = proposal.revisions[0]

    # Finalize the proposal
    if data.proposal?.passed?
      proposal.passed = data.proposal.passed
      proposal.resolved = new Date()
      proposal.resolutions.unshift {
        date: new Date()
        is_resolved: true
        passed: data.proposal.passed
        message: data.proposal.message
        user_id: session.auth?.user_id
        name: data.name
      }
      event_opts.data.passed = data.proposal.passed
      event_opts.data.message = data.proposal.message
    else if data.proposal?.reopened?
      proposal.passed = null
      proposal.resolved = null
      proposal.resolutions.unshift {
        date: new Date()
        is_resolved: false
        passed: null
        message: data.proposal.message
        user_id: session.auth?.user_id
        name: data.name
      }
      event_opts.data.reopened = true
      event_opts.data.message = data.proposal.message

    proposal.save (err, doc) ->
      return callback(err) if err?
      _send_proposal_events(session, doc, event_opts, callback)

  #
  # Append
  #
  r.add_opinion = (session, data, callback) ->
    return callback("Missing proposal id") unless data?.proposal?._id?
    schema.Proposal.findOne {_id: data.proposal._id}, (err, proposal) ->
      unless utils.can_edit(session, proposal)
        return callback("Permission denied.")
      return callback("Missing opinion text") unless data.opinion?.text
      return callback("Missing vote") unless data.opinion?.vote

      event_opts = {
        data: {}
        type: "append"
        user: data.opinion?.user_id or null
      }
      if data.opinion?.user_id?.toString() != session.auth?.user_id
        event_opts.via_user = session.auth?.user_id or null

      if data.opinion?.user_id
        # Authenticated.  Verify that the given ID is in the session
        # user's network. #XXX: Narrow this to the proposal's group?
        user_id = data.opinion.user_id
        user = session.users?[user_id]
        return callback("Unauthorized user id") unless user?
        name = user.name
        # find previous opinion by ID.
        opinion_set = _.find proposal.opinions, (o) ->
          o.user_id == user_id
        event_opts.user = user_id
      else
        # Anonymous opinion.
        user_id = null
        name = data.opinion.name
        opinion_set = _.find proposal.opinions, (o) ->
          (not o.user_id?) and o.name == name

      event_opts.data.user = {name}

      if not opinion_set
        event_opts.data.is_new = true
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
        event_opts.data.is_new = false
        if (opinion_set.revisions.length > 0 and
            opinion_set.revisions[0].text == data.opinion.text and
            opinion_set.revisions[0].vote == data.opinion.vote)
          opinion_set.revisions[0].date = new Date()
        else
          opinion_set.revisions.unshift({
            text: data.opinion.text
            vote: data.opinion.vote
          })

      event_opts.data.text = data.opinion.text
      event_opts.data.vote = data.opinion.vote

      proposal.save (err, doc) ->
        return callback(err) if err?
        _send_proposal_events(session, proposal, event_opts, callback)

  #
  # Trim
  #
  r.remove_opinion = (session, data, callback) ->
    event_opts = {data: {}, type: "trim"}
    schema.Proposal.findOne {_id: data.proposal._id}, (err, proposal) ->
      unless utils.can_edit(session, proposal)
        return callback("Permission denied.")
      found = false
      for opinion, i in proposal.opinions
        if opinion._id.toString() == data.opinion._id.toString()
          op = proposal.opinions.splice(i, 1)[0]
          event_opts.data.vote = op.revisions[0].vote
          found = true
          break
      unless found
        return done("Opinion for `#{data.opinion._id}` not found.")
      proposal.save (err, doc) ->
        return callback(err) if err?
        _send_proposal_events(session, doc, event_opts, callback)

  _send_proposal_events = (session, proposal, event_opts, callback) ->
    async.parallel [
      # Post events.
      (done) ->
        r.post_event(session, proposal, event_opts, 0, done)

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

