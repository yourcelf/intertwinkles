_ = require 'underscore'
async = require 'async'

module.exports = (config) ->
  schema = require("./schema").load(config)
  handlers = require("../../../lib/base_deletion_handler")(config, schema.Firestarter)
  return _.extend(handlers, {
    delete_entity: (params, callback) ->
      ###
      Delete responses as well as firestarters.
      ###
      async.parallel [
        (done) ->
          schema.Response.find {firestarter_id: params.entity}, (err, docs) ->
            return done(err) if err?
            async.map docs, (doc, done) ->
              doc.remove (err) ->
                done(err)
            , done

        (done) ->
          schema.Firestarter.findOne {_id: params.entity}, (err, doc) ->
            doc.remove()
            done(err)
      ], (err) ->
        callback(err)

  })

