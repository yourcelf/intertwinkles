_ = require 'underscore'
async = require 'async'
utils = require '../../../lib/utils'

module.exports = (config) ->
  schema = require("./schema").load(config)
  handlers = require("../../../lib/base_deletion_handler")(config, schema.Dotstorm)
  return _.extend(handlers, {
    trash_entity: (session, params, callback) ->
      ###
      'trash' is used as the array for trashed notes. So use the term
      'archived' instead.
      ###
      schema.Dotstorm.findOne {_id: params.entity}, (err, doc) ->
        return callback(err) if err?
        return callback("Not found") unless doc?
        unless utils.can_edit(session, doc)
          return callback("Permission denied")
        doc.archived = !!params.trash
        doc.save (err, doc) ->
          return callback(err, doc)

    delete_entity: (params, callback) ->
      ###
      Delete images and Idea models as well as Dotstorm model when deleting.
      ###
      async.parallel [
        (done) ->
          schema.Idea.find {dotstorm_id: params.entity}, (err, ideas) ->
            return done(err) if err?
            return done(null) unless ideas?
            async.map ideas, (idea, done) ->
              idea.remove (err) ->
                done(err)
            , done

        (done) ->
          schema.Dotstorm.findOne {_id: params.entity}, (err, dotstorm) ->
            return done(err) if err?
            return done("Not found") unless dotstorm?
            dotstorm.remove()
            done(err)
      ], (err) ->
        callback(err)
  })
