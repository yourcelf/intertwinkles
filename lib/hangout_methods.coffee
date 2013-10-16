async = require "async"
url   = require "url"
utils = require "./utils"

module.exports = (config) ->
  schema = require("./schema").load(config)

  h = {}
  h.validate_url = (session, request_url, callback) ->
    return callback(null, {request_url, valid: false}) unless request_url

    parts = url.parse(request_url)
    # Full URLs only..
    return callback(null, {request_url, valid: false}) if not parts.host

    async.waterfall [
      (done) ->
        # Resolve short URLs
        if parts.href.substring(0, config.short_url_base.length) == config.short_url_base
          short_path = parts.path.replace("/r", "")
          schema.ShortURL.findOne {short_path}, (err, doc) ->
            return done(err) if err?
            return done(null, null, null) unless doc?
            app = doc.application
            long_path = doc.long_path
            done(null, app, long_path)
        else
          # Find the application based on the URL prefix.
          app_key = null
          long_path = null

          for key, app of config.apps
            if key == "www"
              continue
            if parts.href.substring(0, app.url.length) == app.url
              app_key = key
              long_path = parts.href.substring(app.url.length)

          done(null, app_key, long_path)

      (app, long_path, done) ->
        # SearchIndex sharing should equal document sharing. If we are allowed
        # to view the SearchIndex, we are allowed to view the document.
        return done(null, null) unless long_path and app
        schema.SearchIndex.findOne {application: app, url: long_path}, (err, si) ->
          return done(err) if err?
          return done(null, si)

    ], (err, si) ->
      valid = si and utils.can_view(session, si)
      ret = {request_url, valid: si and utils.can_view(session, si)}
      if ret.valid
        ret.doc = si
      return callback(err, ret)

  h.clean_room_docs = (session, docs) ->
    # Clean the docs' sharing, and enforce viewing restrictions.
    cleaned = []
    for doc,i in docs
      if utils.can_view(session, doc)
        as_json = doc.toJSON()
        as_json.sharing = utils.clean_sharing(session, doc)
        cleaned.push(as_json)
      else
        # No permission to view -- only share the URL.
        cleaned.push {absolute_url: doc.absolute_url}
    return cleaned

  return h
