_      = require 'underscore'
config = require './config'
server = require '../lib/server'
models = require '../lib/schema'

module.exports =
  startServer: (opts) ->
    return server.start(_.extend {}, config, opts)
  waitsFor: (callback) ->
    interval = setInterval (-> if callback() then clearInterval interval), 10
  clearDb: (callback) ->
    # Recursive function to delete all documents for the given models, calling
    # mongoose 'remove' hooks to ensure that images, etc. are deleted too.
    deleteDocs = (models, cb, docs=[]) ->
      if models.length == 0 and docs.length == 0
        cb(null)
      else if docs.length == 0
        model = models.pop()
        model.find {}, (err, docs) ->
          if err?
            cb(err)
          else
            deleteDocs(models, cb, docs)
      else
        doc = docs.pop()
        doc.remove (err) ->
          if err?
            cb(err)
          else
            deleteDocs(models, cb, docs)

    deleteDocs([models.Dotstorm, models.Idea, models.IdeaGroup], callback)
