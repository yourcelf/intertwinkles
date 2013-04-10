_             = require 'underscore'
logger        = require './logging'
thumbnails    = require './thumbnails'
utils         = require '../../../lib/utils'


#
# Connect the plumbing for backbone models coming over the socket to mongoose
# models.  Rebroadcast data to rooms as appropriate.
#
attach = (config, sockrooms) ->
  models = require('./schema').load(config)
  events = require('./events')(config)
  sockrooms.on 'dotstorm/backbone', (socket, session, data) ->

    errorOut = (error, level="error") ->
      logger[level](error)
      sockrooms.socketEmit socket, data.signature.event, {error: error}

    respond = (model) ->
      sockrooms.socketEmit socket, data.signature.event, model

    rebroadcast = (room, model) ->
      if room?
        sockrooms.broadcast(room, "dotstorm/backbone", {
          signature: {
            collectionName: data.signature.collectionName
            method: data.signature.method
          }
          model: model
        }, socket.sid)

    saveIdeaAndRespond = (idea, operation) ->
      for key in ["dotstorm_id", "description", "background", "tags",
                  "drawing", "votes", "photoData"]
        if data.model[key]?
          idea[key] = data.model[key]
      if not data.model.tags? and data.model.taglist?
        idea.taglist = data.model.taglist
      models.Dotstorm.findOne {_id: idea.dotstorm_id}, 'name sharing', (err, dotstorm) ->
        return errorOut(err) if err?
        return errorOut("Unknown dotstorm", "warn") unless dotstorm?
        return errorOut("Permission denied", "warn") unless utils.can_edit(session, dotstorm)
        idea.save (err) ->
          return errorOut(err) if err?
          json = idea.serialize()
          delete json.drawing
          respond(json)
          rebroadcast("dotstorm/" + idea.dotstorm_id.toString(), json)
          event_data = {
            is_new: operation == "create"
            description: idea.description
            image: idea.drawingURLs.small
          }
          events.post_event(session, dotstorm, "append", event_data)
          events.post_search_index(dotstorm)

    saveDotstormAndRespond = (doc, event_type) ->
      return errorOut("Permission denied", "warn") unless utils.can_edit(session, doc)
      # Log the event.
      event_data = {}
      for key in ["name", "topic"]
        if data.model[key]? and data.model[key] != doc[key]
          event_data["old_" + key] = doc[key]
          event_data[key] = data.model[key]
      if data.model.groups? and not _.isEqual(data.model.groups, doc.groups)
        event_data.rearranged = true

      # Set the changes to the model
      for key in ["slug", "name", "topic", "groups", "trash"]
        if data.model[key]?
          doc.set key, data.model[key]
      # Sharing has special permissions
      if utils.can_change_sharing(session, doc) and data.model.sharing?
        event_data.sharing = utils.clean_sharing({}, data.model.sharing)
        doc.sharing = data.model.sharing
        # Make sure we can still edit.
        return errorOut("Permission denied", "warn") unless utils.can_edit(session, doc)

      doc.save (err) ->
        if err? then return errorOut(err)
        respond(doc.serialize())
        rebroadcast("dotstorm/" + doc.id, doc)
        events.post_event(session, doc, event_type, event_data)
        events.post_search_index(doc)

    switch data.signature.collectionName
      when "Idea"
        switch data.signature.method
          when "create"
            doc = new models.Idea()
            saveIdeaAndRespond(doc, "create")
          when "update"
            models.Idea.findOne {_id: data.model._id}, (err, doc) ->
              if err? then return errorOut(err)
              saveIdeaAndRespond(doc, "update")
          when "delete"
            return errorOut("Unsupported method `delete`")
          when "read"
            if data.signature.query?
              query = data.signature.query
            else if data.model?
              if data.model._id
                query = {_id: data.model._id}
              else
                query = data.model
                # Remove virtuals before querying...
                delete query.drawingURLs
                delete query.photoURLs
                delete query.taglist
            else
              query = {}
            if data.signature.isCollection
              method = "findLight"
            else
              method = "findOne"
            models.Idea[method] query, (err, doc) ->
              return errorOut(err) if err?
              return errorOut("Idea not found", "warn") unless doc?
              if query.dotstorm_id?
                dotstorm_query = {_id: query.dotstorm_id}
              else if data.model.dotstorm_id?
                dotstorm_query = {_id: data.model.dotstorm_id}
              else
                return errorOut("Unknown dotstorm_id", "warn")
              models.Dotstorm.findOne dotstorm_query, 'name sharing', (err, dotstorm) ->
                return errorOut("Dotstorm not found", "warn") unless dotstorm?
                unless utils.can_view(session, dotstorm)?
                  return errorOut("Permission denied", "warn")
                if data.signature.isCollection
                  respond (m.serialize() for m in (doc or []))
                else
                  respond (doc?.serialize() or {})

      when "Dotstorm"
        switch data.signature.method
          when "create"
            dotstorm = new models.Dotstorm()
            saveDotstormAndRespond(dotstorm, "create")
          when "update"
            models.Dotstorm.findOne {_id: data.model._id}, (err, doc) ->
              saveDotstormAndRespond(doc, "update")
          when "delete"
            return errorOut("Unsupported method `delete`", "warn")
          when "read"
            query = data.signature.query or data.model
            models.Dotstorm.find query, (err, docs) ->
              for doc in docs
                unless utils.can_view(session, doc)
                  return errorOut("Permission denied", "warn")
              if data.signature.isCollection
                respond(docs or [])
              else
                respond(docs?[0] or {})
              if docs?.length > 0
                events.post_event(session, docs[0], "visit", {}, 60 * 1000 * 5)

module.exports = { attach }
