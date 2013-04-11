_     = require 'underscore'
async = require 'async'
utils = require "../../../lib/utils"

module.exports = (config) ->
  schema = require("./schema").load(config)
  api_methods = require("../../../lib/api_methods")(config)
  c = {}

  c.post_event = (session, clock, event_opts={}, timeout=0, callback=(->)) ->
    event = _.extend {
      application: "clock"
      url: clock.url
      entity: clock.id
      user: session.auth?.user_id
      via_user: session.auth?.user_id
      anon_id: session.anon_id
      group: clock.sharing?.group_id
      data: {}
    }, event_opts
    event.data.entity_name = clock.name unless event.data.entity_name?
    api_methods.post_event(event, timeout, callback)

  c.post_search_index = (clock, callback=(->)) ->
    search_data = {
      application: "clock"
      entity: clock.id
      type: "clock"
      url: clock.url
      title: clock.name
      summary: clock.about or(
        cat.name for cat in clock.categories).join(", ")
      sharing: clock.sharing
      text: [clock.name, clock.about or ""].concat(
        cat.name for cat in (clock.categories or [])
      ).join("\n")
    }
    api_methods.add_search_index(search_data, callback)

  c.fetch_clock_list = (session, callback) ->
    utils.list_accessible_documents schema.Clock, session, (err, docs) ->
      return callback(err) if err?
      return callback(null, docs)

  c.fetch_clock = (id, session, callback) ->
    schema.Clock.findOne {_id: id}, (err, doc) ->
      return callback(err) if err?
      return callback("Clock #{id} Not found") unless doc?
      return callback("Permission denied") unless utils.can_view(session, doc)
      return callback(null, doc)

  c.save_clock = (session, data, callback) ->
    return callback("Missing model param") unless data?.model
    schema.Clock.findOne {_id: data.model?._id}, (err, doc) ->
      return callback(err) if err?
      event_opts = {data: {}}
      if not doc
        doc = new schema.Clock()
        event_opts.type = "create"
      else
        event_opts.type = "update"
      return callback("Permission denied") unless utils.can_edit(session, doc)
      # Name and about changes
      for key in ["name", "about"]
        if data.model[key]?
          if event_opts.type == "update"
            event_opts.data["old_" + key] = doc[key]
            event_opts.data[key] = data.model[key]
          doc[key] = data.model[key]
      # Category changes
      if data.model.categories
        if event_opts.type == "update"
          old_cats = _.map(doc.categories, (c) -> c.name).join(", ")
          new_cats = _.map(data.model.categories, (c) -> c.name).join(", ")
          if old_cats != new_cats
            event_opts.data.old_categories = old_cats
            event_opts.data.categories = new_cats
        doc.categories = data.model.categories

      # Sharing changes
      delete data.model.sharing unless utils.can_change_sharing(session, doc)
      if data.model.sharing?
        _.extend(doc.sharing, data.model.sharing)
        if event_opts.type == "update"
          event_opts.data.sharing = utils.clean_sharing({}, data.model.sharing)

      doc.save (err, doc) ->
        return callback(err) if err?
        return callback("null doc") unless doc?
        async.parallel [
          (done) ->
            c.post_event session, doc, event_opts, 0, done
          (done) ->
            c.post_search_index doc, done
        ], (err, results) ->
          return callback(err) if err?
          [event, si] = results
          return callback(null, doc, event, si)

  c.set_time = (session, data, callback) ->
    for key in ["_id", "category", "time", "index", "now"]
      return callback("Missing param #{key}") unless data[key]?
    schema.Clock.findOne {_id: data._id}, (err, doc) ->
      return callback(err) if err?
      return callback("Not found") unless doc?
      return callback("Permission denied") unless utils.can_edit(session, doc)
      category = _.find(doc.categories, (c) -> c.name == data.category)
      return callback("Missing category") unless category?

      now_t = new Date().getTime()
      cutoff_t = new Date().getTime() - 60000
      start_t = new Date(data.time.start).getTime()
      stop_t = if data.time.stop then new Date(data.time.stop).getTime() else null

      save_and_return = -> doc.save(callback)

      if stop_t and not isNaN(stop_t)
        # Stopping a running timer.
        if data.index == category.times.length - 1
          if not category.times[data.index].stop?
            # Check for future, far past, or incoherent times.
            if (stop_t <= now_t and stop_t >= cutoff_t and
                stop_t > category.times[data.index].start.getTime())
              category.times[data.index].stop = new Date(stop_t)
              return save_and_return()
            else
              # Future, far past or incoherent time
              return callback("Bad time", doc)
          else
            # No change -- this timer has already been stopped.
            return callback(null, doc)
        else
          # We're an index ahead or behind. Resync.
          return callback("Out of sync", doc)
      else if start_t and not isNaN(start_t)
        # Starting a new timer.
        if data.index == category.times.length
          # Check for future, far past, or incoherent times.
          prev = category.times[category.times.length - 1]
          if (start_t <= now_t and start_t >= cutoff_t and
              (not prev or prev.stop.getTime() < start_t))
            category.times.push {start: new Date(start_t), stop: null}
            return save_and_return()
          else
            # Future, far past or incoherent time
            return callback("Bad time", doc)
        else if data.index == category.times.length - 1
          # No change -- this timer has already been started.
          return callback(null, doc)
        else
          # We're more than 1 index behind. resync.
          return callback("Out of sync", doc)
      else
        return callback("Bad time", doc)

  return c
