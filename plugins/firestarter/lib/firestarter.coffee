async = require "async"
_     = require "underscore"
utils = require("../../../lib/utils")


module.exports = (config) ->
  schema = require("./schema").load(config)
  api_methods = require("../../../lib/api_methods")(config)

  f = {}

  f.post_event = (session, firestarter, event_opts, timeout, callback) ->
    event = _.extend({
      application: "firestarter"
      entity: firestarter.id
      url: firestarter.url
      user: session.auth?.user_id
      anon_id: session.anon_id
      group: firestarter.sharing?.group_id
      data: {}
    }, event_opts)
    event.data.entity_name = firestarter.name unless event.data.entity_name?
    api_methods.post_event(event, timeout, callback)

  f.post_search = (session, firestarter, responses, callback) ->
    search_content = [firestarter.name, firestarter.prompt].concat(
      (r.response for r in responses)
    ).join("\n")
    terminal_s = if responses.length == 1 then "" else "s"
    api_methods.add_search_index({
      application: "firestarter"
      entity: firestarter.id
      type: "firestarter"
      url: firestarter.url
      title: firestarter.name
      summary: firestarter.prompt + " (#{responses.length} response#{terminal_s})"
      text: search_content
      sharing: firestarter.sharing
    }, callback)


  slug_choices = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  f.get_unused_slug = (callback) ->
    do get_slug = ->
      random_name = (
        slug_choices.substr(
          parseInt(Math.random() * slug_choices.length), 1
        ) for i in [0...6]
      ).join("")
      schema.Firestarter.findOne {slug: random_name}, '_id', (err, doc) ->
        return callback(err) if err?
        if not doc?
          callback(null, random_name)
        else
          get_slug()

  f.get_firestarter = (session, params, callback) ->
    schema.Firestarter.with_responses params, (err, doc) ->
      return callback(err) if err?
      return callback(null, null) unless doc?
      return callback("Permission denied") unless utils.can_view(session, doc)
      f.post_event session, doc, {type: "visit"}, 5 * 60 * 1000, (err, event) ->
        return callback(err, doc, event)

  _handle_firestarter_validation_errors = (err, callback) ->
    errors = []
    if err.name == "ValidationError"
      for field, error of err.errors
        if err.type == "required"
          errors.push({field: field, message: "This field is required."})
        else
          errors.push({field: field, message: error.message})
      return callback("ValidationError", errors)
    else if err.name == "MongoError" and err.err.indexOf("duplicate key") != -1
      errors.push({field: "slug", message: "This name is already taken."})
      return callback("ValidationError", errors)
    else
      return callback(err)

  f.create_firestarter = (session, model, callback) ->
    doc = new schema.Firestarter(model)
    unless utils.can_change_sharing(session, doc)
      return callback("Permission denied")
    doc.save (err, model) ->
      return _handle_firestarter_validation_errors(err, callback) if err?
      async.parallel [
        (done) -> f.post_event(session, doc, {type: "create"}, 0, done)
        (done) -> f.post_search(session, doc, [], done)
      ], (err, results) ->
        return callback(err) if err?
        [event, si] = results
        return callback(null, doc, event, si)

  f.edit_firestarter = (session, model, callback) ->
    schema.Firestarter.findOne {_id: model._id}, (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback("Permission denied") unless utils.can_edit(session, doc)

      event_opts = {type: "update", data: {}}
      for key in ["name", "prompt"]
        if model?[key] and model[key] != doc[key]
          event_opts.data["old_" + key] = doc[key]
          event_opts.data[key] = model[key]
          doc[key] = model[key]
      if utils.can_change_sharing(session, doc) and model.sharing
        utils.update_sharing(doc, model.sharing)
        event_opts.data.sharing = utils.clean_sharing({}, doc)
        # Ensure we can still edit.
        unless utils.can_change_sharing(session, doc)
          return callback("Permission denied")
      doc.save (err, doc) ->
        return _handle_firestarter_validation_errors(err, callback) if err?
        async.parallel [
          (done) -> f.post_event(session, doc, event_opts, 0, done)
          (done) ->
            schema.Response.find {firestarter_id: doc._id}, (err, responses) ->
              return done(err) if err?
              f.post_search(session, doc, responses, done)
        ], (err, results) ->
          return callback(err) if err?
          [event, si] = results
          return callback(null, doc, event, si)

  f.save_response = (session, params, callback) ->
    async.waterfall [
      # Fetch the firestarter and responses
      (done) ->
        schema.Firestarter.findOne {_id: params.firestarter_id}, (err, firestarter) ->
          return done(err) if err?
          return done("Permission denied") unless utils.can_edit(session, firestarter)
          schema.Response.find {firestarter_id: firestarter._id}, (err, responses) ->
            return done(err, firestarter, responses)

      # Update the response.
      (firestarter, responses, done) ->
        event_opts = {
          type: "append"
          data: {text: params.response, user: {name: params.name}}
        }
        if session.auth?.user_id != params.user_id
          event_opts.user = params.user_id or undefined
          event_opts.via_user = session.auth?.user_id
        updates = {
          user_id: params.user_id
          name: params.name
          response: params.response
          firestarter_id: firestarter._id
        }
        if params._id
          event_opts.data.is_new = false
          conditions = {_id: params._id}
          options = {upsert: true, 'new': true}
          schema.Response.findOneAndUpdate conditions, updates, options, (err, doc) ->
            return done(err) if err?
            # Update the responses for the search index
            for orig_response, i in responses
              if orig_response.id == doc.id
                responses.splice(i, 1, doc)
            done(null, firestarter, responses, doc, event_opts)
        else
          event_opts.data.is_new = true
          new schema.Response(updates).save (err, new_response) ->
            return done(err) if err?
            # Update the responses for the search index
            responses.push(new_response)
            # Update the firestarter's list of children.
            firestarter.responses.push(new_response._id)
            firestarter.save (err, firestarter) ->
              done(err, firestarter, responses, new_response, event_opts)
    ], (err, firestarter, responses, new_response, event_opts) ->
      return callback(err) if err?
      # Post search and events.
      async.parallel [
        (done) -> f.post_event(session, firestarter, event_opts, done)
        (done) -> f.post_search(session, firestarter, responses, done)
      ], (err, results) ->
        return callback(err) if err?
        [event, si] = results
        return callback(null, firestarter, new_response, event, si)

  f.delete_response = (session, params, callback) ->
    schema.Firestarter.findOne {_id: params.firestarter_id}, (err, firestarter) ->
      return callback(err) if err?
      return callback("Not found") unless firestarter?
      unless utils.can_edit(session, firestarter)
        return callback("Permission denied")

      schema.Response.find {firestarter_id: firestarter._id}, (err,  responses) ->
        return callback(err) if err?
        deleted_response = null
        for response,i in responses
          if response._id.toString() == params._id.toString()
            deleted_response = responses.splice(i, 1)[0]
            break
        return callback("Response not found") unless deleted_response?
        for response_id, i in firestarter.responses
          if response_id.toString() == params._id.toString()
            firestarter.responses.splice(i, 1)
            break
        event_opts = {
          type: "trim"
          data: { text: deleted_response.response }
        }

        async.parallel [
          (done) -> firestarter.save (err, doc) -> done(err, doc)
          (done) -> deleted_response.remove (err, doc) -> done(err, deleted_response)
          (done) -> f.post_event(session, firestarter, event_opts, done)
          (done) -> f.post_search(session, firestarter, responses, done)
        ], (err, results) ->
          return done(err) if err?
          [firestarter, deleted_response, event, si] = results
          return callback(null, firestarter, deleted_response, event, si)


  return f
