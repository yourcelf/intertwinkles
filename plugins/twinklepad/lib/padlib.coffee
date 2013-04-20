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
    data.entity_name = pad.pad_name
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

  pl.leave_pad = (socket, session, pad_id, callback=(->)) ->
    # Update the search index.
    async.parallel [
      (done) ->
        schema.TwinklePad.findOne {pad_id: pad_id}, (err, doc) ->
          return done(err) if err?
          pl.post_search_index(doc, done)

      (done) ->
        # Remove the session's etherpad_session_id.
        return done() unless session.etherpad_session_id?
        pl.etherpad.deleteSession {
          sessionID: session.etherpad_session_id
        }, done

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
        title: "#{doc.pad_name}"
        summary: summary
        text: text
        sharing: doc.sharing
      }, timeout, callback

  pl.save_pad = (session, data, callback) ->
    unless data.twinklepad?._id? and data.twinklepad?.sharing?
      return callback("Missing twinklepad params")

    schema.TwinklePad.findOne {_id: data.twinklepad._id}, (err, doc) ->
      return callback(err) if err?
      return callback("Twinklepad not found for #{data.twinklepad.pad_id}") unless doc?
      return callback("Permission denied") unless utils.can_change_sharing(
        session, doc
      )
      utils.update_sharing(doc, data.twinklepad.sharing)
      # Make sure they can still change sharing.
      unless utils.can_change_sharing(session, doc)
        return callback("Permission denied")
      async.parallel [
        (done) ->
          doc.save(done)
        (done) ->
          pl.post_search_index(doc, 0, done)
      ], (err) ->
        callback(err, doc)

  pl.get_read_only_html = (doc, callback) ->
    pl.etherpad.getHTML {padID: doc.pad_id}, (err, data) ->
      return callback(err) if err?
      return callback(null, data.html)

  pl.create_pad_session = (session, doc, maxAge, callback) ->
    pl.etherpad.createAuthorIfNotExistsFor {
      authorMapper: session.auth?.user_id or session.anon_id
      name: session.users?[session.auth.user_id]?.name
    }, (err, data) ->
      return done(err) if err?
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

  return pl
