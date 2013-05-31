utils          = require '../../../lib/utils'
_              = require 'underscore'
etherpadClient = require 'etherpad-lite-client'
url            = require 'url'
async          = require 'async'

module.exports = (config) ->
  schema = require('./schema').load(config)
  api_methods = require('../../../lib/api_methods')(config)

  pl = {}

  _pad_url_parts = url.parse(config.apps.twinklepad.etherpad.url)
  pl.etherpad = etherpadClient.connect({
    apikey: config.apps.twinklepad.etherpad.api_key
    host: _pad_url_parts.hostname
    port: _pad_url_parts.port
  })

  pl.post_twinklepad_event = (session, pad, type, data, timeout, callback) ->
    data ?= {}
    data.entity_name = pad.title
    api_methods.post_event {
      application: "twinklepad"
      type: type
      url: "/p/#{pad.pad_name}"
      entity: pad._id
      user: session.auth?.user_id
      anon_id: session.anon_id
      group: pad.sharing?.group_id
      data: data
    }, timeout, callback

  pl.leave_pad = (socket, session, _id, callback=(->)) ->
    # Update the search index.
    async.parallel [
      (done) ->
        schema.TwinklePad.findOne {_id: _id}, (err, doc) ->
          return done(err) if err?
          pl.post_search_index(doc, done)

      (done) ->
        # Remove the session's etherpad_session_id.
        return done() unless session.etherpad_session_id?
        #pl.etherpad.deleteSession {
        #  sessionID: session.etherpad_session_id
        #}, done

    ], callback

  pl.delete_pad = (doc, callback) ->
    pl.etherpad.deletePad {padID: doc.pad_id}, (err, data) ->
      return callback(err)
      #XXX: A bug with dirtydb doubles the "groups" key if we try to delete a group.
      #pl.etherpad.deleteGroup {groupID: doc.etherpad_group_id}, (err, data) ->
      #  return callback(err) if err?
      #  return callback(null)

  pl.post_search_index = (doc, timeout=15000, callback) ->
    pl.etherpad.getText {padID: doc.pad_id}, (err, data) ->
      return callback(err) if err?
      text = data.text
      summary = text.substring(0, 200)
      if summary.length < text.length
        summary += "..."
      api_methods.add_search_index {
        application: "twinklepad"
        entity: doc._id
        type: "etherpad"
        url: "/p/#{encodeURIComponent(doc.pad_name)}"
        title: "#{doc.title}"
        summary: summary
        text: text
        sharing: doc.sharing
      }, timeout, callback

  pl.create_pad = (session, data, callback) ->
    pad = new schema.TwinklePad(data.twinklepad)
    unless utils.can_change_sharing(session, pad)
      return callback("Permission denied")
    pad.save (err, doc) ->
      return callback(err) if err?
      async.parallel [
        (done) ->
          pl.post_twinklepad_event(session, doc, "create", {}, 0, done)
        (done) ->
          pl.create_pad_session_cookie(session, doc, done)
        (done) ->
          pl.post_search_index(doc, 0, done)
      ], (err, results) ->
        return callback(err) if err?
        [event, cookie, si] = results
        callback(err, doc, {session_cookie: cookie}, event, si)

  pl.save_pad = (session, data, callback) ->
    unless data.twinklepad?._id?
      return callback("Missing twinklepad params")

    schema.TwinklePad.findOne {_id: data.twinklepad._id}, (err, doc) ->
      return callback(err) if err?
      return callback("Twinklepad not found for #{data.twinklepad._id}") unless doc?
      delete data.twinklepad.sharing unless utils.can_change_sharing(session, doc)

      if data.twinklepad.name
        doc.name = data.twinklepad.name

      if data.twinklepad.sharing
        utils.update_sharing(doc, data.twinklepad.sharing)
        # Make sure they can still change sharing.
        unless utils.can_change_sharing(session, doc)
          return callback("Permission denied")

      async.parallel [
        (done) -> doc.save (err, doc) -> done(err, doc)
        (done) -> pl.post_search_index(doc, 0, done)
      ], (err, results) ->
        return callback(err) if err?
        [doc, si] = results
        callback(null, doc, si)

  pl.get_read_only_html = (doc, callback) ->
    pl.etherpad.getHTML {padID: doc.pad_id}, (err, data) ->
      return callback(err) if err?
      return callback(null, data.html)

  pl.create_pad_session = (session, doc, maxAge, callback) ->
    pl.etherpad.createAuthorIfNotExistsFor {
      authorMapper: session.auth?.user_id or session.anon_id
      name: session.users?[session.auth.user_id]?.name
    }, (err, data) ->
      return callback(err) if err?
      author_id = data.authorID

      # Set an arbitrary session length of 1 day; though that only matters if
      # the user leaves a tab open and connected for that long.
      valid_until = (new Date().getTime()) + maxAge
      if doc.public_edit_until? or doc.public_view_until?
        valid_until = Math.min(valid_until,
          new Date(doc.public_edit_until or doc.public_view_until).getTime())

      pl.etherpad.createSession {
        groupID: doc.etherpad_group_id
        authorID: author_id
        validUntil: valid_until
      }, (err, data) ->
        return callback(err) if err?
        return callback(null, data.sessionID)

  pl.create_pad_session_cookie = (session, doc, callback) ->
    maxAge = 24 * 60 * 60 * 1000
    pl.create_pad_session session, doc, maxAge, (err, pad_session_id) ->
      return callback(err) if err?
      session.etherpad_session_id = pad_session_id
      cookie = {
        value: pad_session_id
        params: {
          path: "/",
          expires: 1,
          domain: config.apps.twinklepad.etherpad.cookie_domain
        }
      }
      return callback(null, cookie)

  pl.fetch_pad = (session, params, callback) ->
    schema.TwinklePad.findOne {pad_name: params.pad_name}, (err, doc) ->
      return callback(err) if err?
      return callback(err, null) unless doc?
      return callback("Permission denied") unless utils.can_view(session, doc)

      respond = (doc, extras) ->
        pl.post_twinklepad_event session, doc, "visit", {}, 1000 * 60 * 5, (err, event) ->
          callback(err, doc, extras, event)

      # Get pad session, or read only html.
      extras = {}
      if utils.can_edit(session, doc)
        # Establish an etherpad auth session. Get the author mapper / author name
        pl.create_pad_session_cookie session, doc, (err, cookie) ->
          return callback(err) if err?
          extras.session_cookie = cookie
          return respond(doc, extras)
      else
        # Display read only.
        pl.get_read_only_html doc, (err, html)->
          return callback(err) if err?
          extras.text = html
          return respond(doc, extras)

  return pl
