_ = require 'underscore'
fs = require "fs"
logger = require("log4js").getLogger()
async = require "async"
icons = require "./icons"

BASE = __dirname + "/"

# Wrap fs.exists to use null as first argument to done, for better
# compatability with async.
exists = (path, cb) -> fs.exists path, (exists) -> cb(null, exists)

# Ensure that each icon for a particular user exists.
check_user_icons = (user, cb) ->
  paths = (BASE + user.icon.sizes[k] for k in ["16", "32", "64"])
  unless _.every(paths, (p) -> !!p)
    cb(null, [user, false])
  else
    async.map(paths, exists, (err, results) ->
      cb(null, [user, _.every(results, (r) -> r)])
    )

rebuild_icon = (user, cb) ->
  if user?.icon?.pk and user?.icon?.color
    icons.render_icon(user.icon.pk, user.icon.color, cb)

module.exports = fix_icons = (config, callback) ->
  schema = require("./schema").load(config)
  schema.User.find {}, {'icon'}, (err, users) ->
    return callback(err) if err?
    async.waterfall [
      (done) ->
        needs_fix = []
        async.map users, check_user_icons, (err, results) ->
          return callback(err) if err?
          for result in results
            [user, all_exists] = result
            unless all_exists
              needs_fix.push(user)
          done(null, needs_fix)

      (needs_fix, done) ->
        logger.info("#{needs_fix.length} users missing icons.")
        async.map(needs_fix, rebuild_icon, done)

    ], (err, results) ->
      return callback(err) if err?
      logger.info("#{results.length} icons rebuilt.")
      callback()
