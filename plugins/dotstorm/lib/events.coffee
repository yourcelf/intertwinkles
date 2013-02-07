intertwinkles = require 'node-intertwinkles'
schema        = require './schema'
_             = require 'underscore'
logger        = require('log4js').getLogger()

module.exports = (config) ->
  return {
    post_event: (session, dotstorm, type, opts) =>
      opts or= {}
      event = _.extend {
          application: "dotstorm"
          type: type
          entity_url: "/dotstorm/d/#{dotstorm.slug}/"
          entity: dotstorm._id
          user: session.auth?.user_id
          via_user: session.auth?.user_id
          anon_id: session.anon_id
          group: dotstorm.sharing?.group_id
          data: _.extend {
            title: dotstorm.name or "Untitled"
          }, opts.data or {}
        }, opts.overrides or {}
      intertwinkles.post_event(event, config, opts.callback or (->), opts.timeout)

    post_search_index: (doc, callback) =>
      unless doc?
        error = "Can't post search index for `#{doc}`"
        logger.error(error)
        return callback?(error)


      schema.Dotstorm.withLightIdeas {_id: doc._id}, (err, dotstorm) ->
        if err?
          logger.error(err)
          return callback?(err)
        unless dotstorm?
          error = "Dotstorm #{doc._id} not found."
          logger.error(error)
          return callback?(error)

        stuff = []
        stuff.push(dotstorm.name) if dotstorm.name?
        stuff.push(dotstorm.topic) if dotstorm.topic?

        untrash_count = 0
        for group in dotstorm.groups
          stuff.push(group.label) if group.label?
          for idea in group.ideas
            stuff.push(idea.description) if idea.description
            for tag in idea.tags or []
              stuff.push(tag)
              untrash_count += 1

        if stuff.length > 0
          search_data = {
            application: "dotstorm"
            entity: dotstorm._id
            type: "dotstorm"
            url: "/dotstorm/d/#{dotstorm.slug}/"
            title: dotstorm.name or "Untitled dotstorm"
            summary: "#{dotstorm.topic or ""} " +
              "(#{untrash_count} idea#{if untrash_count == 1 then "" else "s"})"
            text: stuff.join("\n")
            sharing: dotstorm.sharing
          }
          intertwinkles.post_search_index(search_data, config, callback)
  }
