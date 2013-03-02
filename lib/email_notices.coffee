_     = require 'underscore'
async = require 'async'

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

  render_notifications = (template_path, context, callback) ->
    formats = {}
    respond = (err) ->
      callback(err, formats)
    context = _.extend({
      subscription_settings_link: config.api_url + "/profile/edit/"
      static_url: config.api_url + "/static/"
      home_url: config.apps.www.url
    }, context)

    view = require(template_path)
    formats.web = view.web(context) if view.web
    if view.email.subject
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

  return { send_notifications, render_notifications }

module.exports = { load }

