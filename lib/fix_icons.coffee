###
Utility script to fix missing user icons.
###

_ = require 'underscore'
fs = require "fs"
path = require 'path'
logger = require("log4js").getLogger()
async = require "async"
icons = require "./icons"

BASE = __dirname + "/../uploads/"
SIZES = ["16", "32", "64"]

exists_with_base = (path, cb) ->
  fs.exists BASE + path, (exists) ->
    cb(null, exists)

# Ensure that each icon for a particular user exists.
check_user_icons = (user, cb) ->
  paths = (user.icon.sizes[k] for k in SIZES)
  unless _.every(paths, (p) -> !!p)
    cb(null, [user, false])
  else
    async.map(paths, exists_with_base, (err, results) ->
      all_exist = _.every(results, (r) -> r)
      all_normal = true
      if all_exist
        # Ensure that the paths are properly normalized.
        for filepath in paths
          rel = path.relative(BASE, BASE + filepath)
          if rel != filepath
            console.log rel, filepath
            all_normal = false
            break
      cb(null, [user, all_exist and all_normal])
    )

# Draw the icon.
rebuild_icon = (user, cb) ->
  if user?.icon?.pk and user?.icon?.color
    icons.render_icon(user.icon.pk, user.icon.color, (err, icon) ->
      return cb(err) if err?
      user.icon = icon
      user.save (err, user) ->
        return cb(err, true))
  else
    cb(null, false)

module.exports = fix_icons = (config, callback) ->
  schema = require("./schema").load(config)
  # Grab all the users.
  schema.User.find {}, {'icon'}, (err, users) ->
    return callback(err) if err?

    async.waterfall [
      (done) ->
        # Find the users who have missing icons.
        needs_fix = []
        async.map users, check_user_icons, (err, results) ->
          return callback(err) if err?
          for result in results
            [user, all_exists] = result
            unless all_exists
              needs_fix.push(user)
          done(null, needs_fix)

      (needs_fix, done) ->
        # Render the icons for missing users.
        logger.info(
          "#{needs_fix.length} of #{users.length} users missing icons."
        )
        async.map(needs_fix, rebuild_icon, done)

    ], (err, results) ->
      # All done.
      return callback(err) if err?
      fixed = 0
      skipped = 0
      for result in results
        if result
          fixed += 1
        else
          skipped += 1
      logger.info("#{fixed} users' icons fixed.")
      if skipped > 0
        logger.info("#{skipped} users were skipped due to missing fields.")
      callback()
