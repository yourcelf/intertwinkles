Canvas   = require 'canvas'
fs       = require 'fs'
path     = require 'path'
logger   = require './logging'
im       = require 'imagemagick'

BASE_PATH = __dirname + "/../assets"

sizes =
  # Sizes allow for 1px border, and fit well on mobile screens (240px, 480px)
  small: [78, 78]
  medium: [118, 118]
  large: [238, 238]
  full: [640, 640]

mkdirs = (dir, mode, callback) ->
  # Make the directory, and any parent directories needed.
  fs.stat dir, (err, stats) ->
    if err?
      if err.code == "ENOENT"
        # Dir doesn't exist.  Walk up the tree.
        mkdirs dir.split("/").slice(0, -1).join("/"), mode, (err) ->
          if err? then return callback?(err)
          fs.mkdir dir, mode, (err) ->
            # Ignore EEXIST; the dir could've been created while asynchronously
            # while we were waiting (especially when importing/resaving
            # images).
            if err? and err.code != "EEXIST" then return callback?(err)
            return callback(null)
      else
        return callback?(err)
    else
      if stats.isDirectory()
        return callback?(null)
      return callback?(err)

clearDir = (dir, callback) ->
  # Remove everything in the given directory.
  logger.debug "clearing #{dir}"
  mkdirs dir, "0775", (err) ->
    if err then return callback?(err)
    fs.readdir dir, (err, files) ->
      if err then return callback?(err)
      numFiles = files.length
      if numFiles == 0
        callback?(null)
      else
        for file in files
          fs.unlink "#{dir}/#{file}", (err) ->
            if err then return callback?(err)
            numFiles -= 1
            if numFiles == 0 then callback?(null)

getThumbnailDims = (origx, origy, maxx, maxy) ->
  # Get the maximum dimensions that fit in maxx, maxy while preserving aspect
  # ratio.
  aspect = origx / origy
  if aspect > 1
    return [maxx, maxy / aspect]
  return [maxx * aspect, maxy]

canvas2thumbnails = (canvas, thumbnails, callback) ->
  # Given a canvas and an array of thumbnail definitions in the form:
  #   [[ <destination_path>, <maxx>, <maxy> ]]
  # create thumbnail files on disk.
  logger.debug "building thumbnails...", thumbnails
  logger.debug "libcairo #{Canvas.cairoVersion}"
  img = canvas.toBuffer (err, buf) ->
    if err then return callback?(err)
    logger.debug "buffer loaded."
    count = thumbnails.length
    for data in thumbnails
      do (data) ->
        logger.debug "processing #{data}"
        [dest, maxx, maxy] = data
        dims = getThumbnailDims(canvas.width, canvas.height, maxx, maxy)
        thumb = new Canvas(dims[0], dims[1])
        img = new Canvas.Image
        img.src = buf
        logger.debug "image loaded."
        ctx = thumb.getContext('2d')
        logger.debug "context loaded."
        ctx.drawImage(img, 0, 0, dims[0], dims[1])
        logger.debug "Writing file #{dest}"
        out = fs.createWriteStream dest
        stream = thumb.createPNGStream()
        stream.on 'data', (chunk) ->
          out.write chunk
        stream.on 'end', ->
          count -= 1
          if count == 0
            callback?(null)

drawIdeaToCanvas = (idea, callback) ->
  # Render the drawing instructions contained in the idea to a canvas.
  logger.debug "drawing #{idea.id}"
  dims = idea.DIMS
  canvas = new Canvas dims.x, dims.y
  ctx = canvas.getContext('2d')
  
  # Draw background
  ctx.fillStyle = idea.get("background")
  ctx.fillRect(0, 0, dims.x, dims.y)
  ctx.fillStyle = "#000000"

  drawOverlay = ->
    # Draw lines
    ctx.lineCap = 'round'
    lastTool = null
    for [tool, x1, y1, x2, y2] in idea.get("drawing")
      if tool != lastTool
        switch tool
          when "pencil"
            ctx.lineWidth = 8
            ctx.strokeStyle = '#000000'
          when "eraser"
            ctx.lineWidth = 32
            ctx.strokeStyle = idea.get("background")
        lastTool = tool
      ctx.beginPath()
      if x1?
        ctx.moveTo x1, y1
      else
        ctx.moveTo x2, y2
      ctx.lineTo x2, y2
      ctx.stroke()

    # Draw description
    totalLines = 10
    ctx.font = (dims.y / totalLines) + "px Arial"
    lineNum = 0
    for line in idea.get("description").split("\n")
      lineNum += 1
      words = line.split(" ")
      x = 0
      for word in words
        word = word + " "
        width = ctx.measureText(word).width
        if x + width > dims.x
          x = 0
          lineNum += 1
        # HACK: 10px offset found by experimentation to line up better.
        ctx.fillText(word, x, (dims.y / totalLines) * lineNum - 10)
        x += width
    callback(canvas)

  # Draw image....
  photoPath = idea.getPhotoPath("full")
  if photoPath?
    fs.readFile photoPath, (err, buffer) ->
      if (err) then throw err
      img = new Canvas.Image
      img.src = buffer
      # Note: assuming 3x4 aspect ratio.
      ctx.drawImage(img, 0, 1/4 * dims.y, dims.x, 3/4 * dims.y)
      drawOverlay()
  else
    drawOverlay()

shrink = (buffer, thumbs, callback) ->
  # Given a binary image buffer, and a list of paths and sizes:
  #   [<path>, width, height]
  # create the thumbnails.
  count = thumbs.length
  for thumb in thumbs
    logger.debug "Writing #{thumb[0]} (#{thumb[1]}x#{thumb[2]})"
    im.resize
      dstPath: thumb[0]
      srcData: buffer
      width: thumb[1]
      height: thumb[1]
      format: 'jpg'
    , (err) ->
      if err then return callback?(err)
      count -= 1
      if count == 0 then return callback?(null)

drawingThumbs = (idea, callback) ->
  # Create thumbnail images for the given idea.
  fs.exists idea.getDrawingPath("small"), (exists) ->
    if exists
      callback?(null)
      logger.debug("skipping thumbnail; already exists")
    else
      clearDir path.dirname(idea.getDrawingPath("small")), (err) ->
        if (err) then return callback?(err)
        drawIdeaToCanvas idea, (canvas) ->
          buffer = canvas.toBuffer()
          thumbs = []
          for name, size of sizes
            thumbs.push [idea.getDrawingPath(name), size[0], size[1]]
          shrink buffer, thumbs, (err) ->
            if err?
              callback?(err)
            else
              callback?(null)

photoThumbs = (idea, photoData, callback) ->
  unless idea.photoVersion?
    return callback?("missing photo version")
  fs.exists idea.getPhotoPath("small"), (exists) ->
    if exists
      callback?(null)
      logger.debug("skipping photo; already exists")
    else
      clearDir path.dirname(idea.getPhotoPath("small")), (err) ->
        if (err) then return callback?(err)
        buffer = new Buffer(photoData, 'base64').toString('binary')
        thumbs = []
        for name, size of sizes
          thumbs.push [idea.getPhotoPath(name), size[0], size[1]]
        shrink buffer, thumbs, (err) ->
          if err?
            callback?(err)
          else
            callback?(null)

remove = (model, callback) ->
  dirs = []
  for file in [model.getDrawingPath("small"), model.getPhotoPath("small")]
    if file?
      dirs.push path.dirname(file)

  error = null
  count = dirs.length
  for dir in dirs
    do (dir) ->
      logger.debug "removing #{dir} and all contents"
      clearDir dir, (err) ->
        if err?
          logger.error(err)
          error = err
        fs.rmdir dir, (err) ->
          if err?
            logger.error(err)
            error = err
          count -= 1
          if count == 0
            # Remove parent dir
            fs.rmdir path.dirname(dir), (err) ->
              if err?
                logger.error(err)
                error = err
              callback(error)

module.exports = { drawingThumbs, photoThumbs, remove, BASE_PATH }
