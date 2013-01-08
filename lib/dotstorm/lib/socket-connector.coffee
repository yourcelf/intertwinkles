logger        = require './logging'
models        = require './schema'
thumbnails    = require './thumbnails'
intertwinkles = require 'node-intertwinkles'


#
# Connect the plumbing for backbone models coming over the socket to mongoose
# models.  Rebroadcast data to rooms as appropriate.
#
attach = (config, iorooms) ->
  events = require('./events')(config)
  iorooms.onChannel 'backbone', (socket, data) ->
    session = socket.session

    errorOut = (error) ->
      logger.error(error)
      socket.emit(data.signature.event, error: error)

    respond = (model) ->
      socket.emit(data.signature.event, model)

    rebroadcast = (room, model) ->
      if room?
        socket.broadcast.to(room).emit "backbone", {
          signature: {
            collectionName: data.signature.collectionName
            method: data.signature.method
          }
          model: model
        }

    saveIdeaAndRespond = (idea) ->
      for key in ["dotstorm_id", "description", "background", "tags",
                  "drawing", "votes", "photoData"]
        if data.model[key]?
          idea[key] = data.model[key]
      if not data.model.tags? and data.model.taglist?
        idea.taglist = data.model.taglist
      models.Dotstorm.findOne {_id: idea.dotstorm_id}, 'sharing', (err, dotstorm) ->
        return errorOut(err) if err?
        return errorOut("Unknown dotstorm") unless dotstorm?
        return errorOut("Permission denied") unless intertwinkles.can_edit(session, dotstorm)
        idea.save (err) ->
          return errorOut(err) if err?
          json = idea.serialize()
          delete json.drawing
          respond(json)
          rebroadcast(idea.dotstorm_id, json)
          events.post_event(session, dotstorm, "append", {data: json})
          events.post_search_index(dotstorm)

    saveDotstormAndRespond = (doc) ->
      return errorOut("Permission denied") unless intertwinkles.can_edit(session, doc)
      event_type = if doc._id then "update" else "create"
      for key in ["slug", "name", "topic", "groups", "trash"]
        if data.model[key]?
          doc.set key, data.model[key]
      # Sharing has special permissions
      if intertwinkles.can_change_sharing(session, doc) and data.model.sharing?
        doc.sharing = data.model.sharing
        # Make sure we can still edit.
        return errorOut("Permission denied") unless intertwinkles.can_edit(session, doc)
      doc.save (err) ->
        if err? then return errorOut(err)
        respond(doc.serialize())
        rebroadcast(doc._id, doc)
        events.post_event(session, doc, event_type)
        events.post_search_index(doc)

    switch data.signature.collectionName
      when "Idea"
        switch data.signature.method
          when "create"
            doc = new models.Idea()
            saveIdeaAndRespond(doc)
          when "update"
            models.Idea.findOne {_id: data.model._id}, (err, doc) ->
              if err? then return errorOut(err)
              saveIdeaAndRespond(doc)
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
              return errorOut("Idea not found") unless doc?
              if query.dotstorm_id?
                dotstorm_query = {_id: query.dotstorm_id}
              else if data.model.dotstorm_id?
                dotstorm_query = {_id: data.model.dotstorm_id}
              else
                return errorOut("Unknown dotstorm_id")
              models.Dotstorm.findOne dotstorm_query, 'sharing', (err, dotstorm) ->
                return errorOut("Dotstorm not found") unless dotstorm?
                unless intertwinkles.can_view(session, dotstorm)?
                  return errorOut("Permission denied")
                if data.signature.isCollection
                  respond (m.serialize() for m in (doc or []))
                else
                  respond (doc?.serialize() or {})

      when "Dotstorm"
        switch data.signature.method
          when "create"
            dotstorm = new models.Dotstorm()
            saveDotstormAndRespond(dotstorm)
          when "update"
            models.Dotstorm.findOne {_id: data.model._id}, (err, doc) ->
              saveDotstormAndRespond(doc)
          when "delete"
            return errorOut("Unsupported method `delete`")
          when "read"
            query = data.signature.query or data.model
            models.Dotstorm.find query, (err, docs) ->
              for doc in docs
                unless intertwinkles.can_view(session, doc)
                  return errorOut("Permission denied")
              if data.signature.isCollection
                respond(docs or [])
              else
                respond(docs?[0] or {})
              if docs?.length > 0
                events.post_event(session, docs[0], "view", {timeout: 60 * 1000 * 5})

module.exports = { attach }
