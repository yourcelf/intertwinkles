###
Methods to add and remove uploaded images, and to create thumbnails for them.
###
fs    = require 'fs'
path  = require 'path'
im    = require 'imagemagick'
_     = require 'underscore'

upload = (filePath, dest, callback) ->
  # Write the original.
  ext = path.extname(filePath)
  base = __dirname + "/../uploads"
  fullSizePath = base + dest + "/" + path.basename(filePath)
  thumbPath    = path.dirname(fullSizePath) + "/" + path.basename(filePath, ext) + "_thumb" + ext
  fs.readFile filePath, (err, data) ->
    return callback?(err) if err?
    fs.writeFile fullSizePath, data, (err) ->
      return callback?(err) if err?
      im.resize {
        dstPath: thumbPath
        srcPath: fullSizePath
        height: 64
        format: 'png'
      }, (err) -> callback? null, {
        full: path.relative(base, fullSizePath)
        thumb: path.relative(base, thumbPath)
      }

remove = (files, assetBase, callback) ->
  base = __dirname + "/../uploads/"
  safety_base = path.normalize(base + assetBase)
  count = files.length
  errors = []
  _.each files, (file) ->
    full_path = path.normalize(base + file)
    if not full_path.substring(0, safety_base).length == safety_base
      errors.push({error: "Given path #{full_path} is not safe."})
    fs.unlink full_path, (err) ->
      if err? and err.code != 'ENOENT'
        # Ignore 'file not found' errors.
        errors.push(err) if err?
      count -= 1
      if count == 0
        if errors.length > 0
          return callback?(errors)
        return callback?(null)

module.exports = {upload, remove}
