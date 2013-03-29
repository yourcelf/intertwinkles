###
# This is a utility module to load v1 tenpoints boards from their redis data
# store into InterTwinles and mongodb.
###
async     = require 'async'
mongoose  = require 'mongoose'
_         = require 'underscore'
require "better-stack-traces"

module.exports = {
  run: (config, jsonpath) ->
    schema = require("./schema").load(config)
    pointslib = require("./pointslib")(config)
    db = mongoose.connect(
      "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
    )
    olduns = require(jsonpath)
    queue = ([key, data] for key, data of olduns)

    create_vote  = (_id, point_id, voter, cb) ->
      return cb() unless voter
      pointslib.change_support {}, {
        _id: _id, point_id: point_id, name: voter, vote: true
      }, cb

    create_point = (_id, text, votes, cb) ->
      return cb() unless text
      user = _.find(votes, (v) -> not not v)
      return cb() unless user
      pointslib.revise_point {}, {
        _id, text, name: user
      }, (err, doc, point) ->
        return cb(err) if err?
        # We need series operation here as point creation and vote creation
        # modify the same lists, and trigger a version mismatch error if they
        # happen in parallel.
        async.mapSeries(votes, (voter, done) ->
          create_vote(_id, point._id, voter, done)
        , cb)

    async.map queue, (data, done) ->
      slug = data[0].replace("billofrights:shared_rights:", "")
      points = data[1]
      if not _.any(points, (p) -> not not p.message)
        console.log("Skipping #{slug}; empty")
        return done()

      schema.PointSet.findOne {slug: slug}, (err, doc) ->
        return done(err) if err?
        if doc?
          console.log("Skipping #{slug}; already exists")
          return done()

        console.log("Creating #{slug}")
        pointslib.save_pointset {}, {
          model: {
            name: slug.replace(/[-]/g, " ")
            slug: slug
          }
        }, (err, doc) ->
          return done(err) if err?
          # Add points in series (see above).
          async.mapSeries points, (point, done) ->
            create_point(doc._id, point.message, point.votes, done)
          , done
    , (err, results) ->
      console.error(err) if err?
      db.disconnect()
}
