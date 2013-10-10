###
Copy all the files in the various 'assets' folders into one place.  This is a
similar strategy to 'collectstatic' from the Django world.
###
fs        = require 'fs'
path      = require 'path'
async     = require 'async'
logger    = require('log4js').getLogger('assets')

# plugin path
asset_folders = [
  __dirname + "/../assets",
  __dirname + "/../plugins/dotstorm/assets",
  __dirname + "/../plugins/resolve/assets",
  __dirname + "/../plugins/firestarter/assets",
  __dirname + "/../plugins/twinklepad/assets",
  __dirname + "/../plugins/clock/assets",
  __dirname + "/../plugins/points/assets",
]

mkdirs = (dir) ->
  if fs.existsSync(dir)
    return
  else
    parent = path.dirname(dir)
    mkdirs(parent)
    fs.mkdirSync(dir)

copy_files = (dir, parent, destRoot) ->
  for name in fs.readdirSync(dir)
    full_name = path.normalize(dir + "/" + name)
    stats = fs.statSync(full_name)
    if stats.isDirectory()
      copy_files(full_name, parent, destRoot)
    else
      rel_name = path.relative(parent, full_name)
      dest = destRoot + "/" + rel_name
      mkdirs(path.dirname(dest))
      fs.writeFileSync(dest, fs.readFileSync(full_name))

compile_all = (destRoot) ->
  destRoot = path.normalize(destRoot)
  # Copy *all* the assets to the destination.
  for dir in asset_folders
    copy_files(dir, dir, destRoot)

module.exports = {compile_all}
