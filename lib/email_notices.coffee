_     = require 'underscore'
async = require 'async'
utils = require "./utils"

load = (config) ->
  client = require("emailjs").server.connect(config.email)
  schema = require("./schema").load(config)
  api_methods = require("./api_methods")(config)

  newline_chars = /[\n\r]/
  validate_headers = (params) ->
    for key in ["from", "to", "subject"]
      if newline_chars.test(params[key])
        return false
    return true

  send_email = (params, callback) ->
    if validate_headers(params)
      client.send(params, callback)
    else
      callback("Invalid header found")

  send_custom_group_message = (session, params, callback) ->
    return callback("Not authenticated") unless utils.is_authenticated(session)
    for key in ["group_id", "subject", "body"]
      return callback("Missing param #{key}") unless params[key]?
    from = session.users[session.auth.user_id]
    return "Unknown sender" unless from
    unless session?.groups?[params.group_id]
      return callback("Unauthorized group")
    unless params.subject.trim() and params.body.trim()
      return callback("Missing subject or body")
    recipients = []
    for member in session.groups[params.group_id].members
      recipient = session.users[member.user]
      return callback("Unknown member in group!") unless recipient?
      recipients.push(recipient.email)

    # From/Sender/Reply-to strategy from http://stackoverflow.com/a/14555043
    send_email({
      sender: config.from_email
      from: "\"#{from.name.replace(/["]/g, "")} (via InterTwinkles)\" <#{config.from_email}>"
      "reply-to": from.email
      to: recipients.join(", ")
      subject: params.subject.trim()
      text: params.body.trim()
    }, callback)

  send_notifications = (callback=(->)) ->
    schema.Notification.findSendable {}, (err, docs) ->
      email_queue = []
      sms_queue = []

      for doc in docs
        if doc.formats.sms?
          if doc.recipient.notifications[doc.type].sms and doc.recipient.mobile.number?
            sms_queue.push(doc)
          doc.sent.sms = new Date()
        if doc.formats.email?
          if doc.recipient.notifications[doc.type].email
            email_queue.push(doc)
          doc.sent.email = new Date()

      # Save the sent status of the documents first -- better to not send a
      # notice than to double-send if there's an error.
      async.map docs, ((doc, done) -> doc.save(done)), (err) ->
        callback(err) if err?
        # ... then send the notification emails.
        async.parallel [
          # Send sms
          (done) ->
            async.map sms_queue, (doc) ->
                params = {
                  from: config.from_email
                  to: doc.recipient.sms_address.trim()
                  subject: doc.formats.sms
                  text: " "
                }
                send_email(params, done)
            , done

          # Send email
          (done) ->
            async.map email_queue, (doc, done) ->
              params = {
                from: config.from_email
                to: doc.recipient.email
                subject: doc.formats.email.subject
              }
              if doc.formats.email.text
                params.text = doc.formats.email.text
              if doc.formats.email.html
                params.attachment = [{
                  data: doc.formats.email.html
                  alternative: true
                }]
              send_email(params, done)
            , done
        ], (err) ->
          callback(err, docs)

  render_notifications = (view, context, callback) ->
    formats = {}
    respond = (err) -> callback(err, formats)
    context = _.extend({
      subscription_settings_link: config.api_url + "/profiles/edit/"
      static_url: config.api_url + "/static/"
      home_url: config.apps.www.url
    }, context)

    formats.web = view.web(context) if view.web
    if view.email?.subject
      formats.email = {}
      formats.email.subject = view.email.subject(context)
      context.subject = formats.email.subject
      formats.email.text = view.email.text(context) if view.email.text
      formats.email.html = view.email.html(context) if view.email.html
    if view.sms
      api_methods.make_short_url context.url, context.application, (err, short_doc) ->
        return respond(err) if err?
        context.short_url = short_doc.absolute_short_url
        formats.sms = view.sms(context).substring(0, 160)
        return respond(null, formats)
    else
      return respond(null, formats)

  activity_summary_view = require("../emails/activity_summary")
  render_daily_activity_summary = (user, date, callback) ->
    end = date
    start = new Date(end.getTime() - 24 * 60 * 60 * 1000)
    activity_url = "/activity/for/#{end.getFullYear()}/#{end.getMonth() + 1}/#{end.getDate()}/"
    prev = new Date(end.getTime() - 25 * 60 * 60 * 1000)
    prev_url = "/activity/for/#{prev.getFullYear()}/#{prev.getMonth() + 1}/#{prev.getDate()}/"
    next = new Date(end.getTime() + 25 * 60 * 60 * 1000)
    next_url = "/activity/for/#{next.getFullYear()}/#{next.getMonth() + 1}/#{next.getDate()}/"
    async.waterfall [
      (done) ->
        api_methods.get_groups(user, done)

      (users_groups, done) ->
        api_methods.get_event_user_hierarchy {
          users: users_groups.users
          groups: users_groups.groups,
          start: start,
          end: end,
          user_id: user.id,
        }, (err, hierarchy, notices) ->
          done(err, hierarchy, notices)

      (hierarchy, notices, done) ->
        # We don't want to send bare invites; this is spam. No linked-in-ish-ness.
        notice_types = _.uniq(n.type for n in notices)
        only_invite = notice_types.length == 1 and notice_types[0] == "invitation"
        unless (hierarchy?.length or (notices?.length and not only_invite))
          return done()
        visits = 0
        edits = 0
        for g in hierarchy
          for u in g.users
            for e in u.entities
              for c in e.collectives
                for event in c.events
                  if event.type == "visit"
                    visits += 1
                  else
                    edits += 1

        context = {
          recipient: user
          date: date
          start: start
          end: end
          hierarchy: hierarchy
          notices: notices
          todos: notices.length
          visits: visits
          edits: edits
          static_url: config.api_url + "/static/"
          home_url: config.apps.www.url
          show_url: config.api_url + activity_url
          prev_url: prev_url
          next_url: next_url
          subscription_settings_link: config.api_url + "/profiles/edit/"
          absolutize_url: (given_url) ->
            utils.absolutize_url(config.api_url, given_url)
          conf: { apps: config.apps }
        }
        formats = {}
        async.parallel [
          (done) ->
            unless user.notifications.activity_summaries.sms and user.sms_address?
              return done()
            api_methods.make_short_url activity_url, "www", (err, short) ->
              return done(err) if err?
              context.short_url = short.absolute_short_url
              formats.sms = activity_summary_view.sms(context)
              done()
          (done) ->
            return done() unless user.notifications.activity_summaries.email
            formats.email = {
              subject: activity_summary_view.email.subject(context)
              text: activity_summary_view.email.text(context)
              html: activity_summary_view.email.html(context)
            }
            done()
        ], (err) ->
          return done(err) if err?
          return done(null, formats)
    ], (err, formats) ->
      callback(err, formats)

  send_daily_activity_summaries = (callback=(->)) ->
    # XXX: This is massively inefficient, but it will run in a separate thread
    # from the web worker, called by cron. It could be optimized 6 ways from
    # sunday by trying a little, but keeping it simple for now.
    return callback(err) if err?
    schema.User.find {$or: [
      {'notifications.activity_summaries.sms': true}
      {'notifications.activity_summaries.email': true}
    ]}, (err, users) ->
      return callback(err) if err?
      sent_count = 0
      date = new Date()
      async.map users, (user, done) ->
        render_daily_activity_summary user, date, (err, formats) ->
          return done(err) if err?
          return done() unless formats?
          async.parallel [
            # Send sms
            (done) ->
              return done() unless formats.sms?
              sent_count += 1
              send_email({
                from: config.from_email
                to: user.sms_address.trim()
                subject: formats.sms
                text: " "
              }, done)

            # Send email
            (done) ->
              return done() unless formats.email?
              sent_count += 1
              send_email({
                from: config.from_email
                to: user.email
                subject: formats.email.subject
                text: formats.email.text
                attachment: {
                  data: formats.email.html
                  alternative: true
                }
              }, done)
            ], done
      , (err) ->
        return callback(err, sent_count)


  return {
    send_notifications, render_notifications,
    send_daily_activity_summaries, render_daily_activity_summary,
    send_custom_group_message
  }

module.exports = { load }

