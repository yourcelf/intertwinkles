mongoose   = require 'mongoose'
Schema     = mongoose.Schema
uuid       = require 'node-uuid'
_          = require 'underscore'
thumbnails = require './thumbnails'

load = (config) ->
  #
  # Ideas
  #

  # Idea
  IdeaSchema = new Schema
    author: { type: Schema.ObjectId, ref: 'User' }
    votes: { type: Number, default: 0 }
    dotstorm_id: { type: Schema.ObjectId, required: true }
    imageVersion: {
      type: Number
      set: (v) ->
        if v != @imageVersion then @_updateThumbnails = true
        return v
    }
    photoVersion: {
      type: Number
      set: (v) ->
        if v != @photoVersion then @incImageVersion()
        return v
    }
    background: {
      type: String
      set: (v) ->
        if v != @background then @incImageVersion()
        return v
    }
    description: {
      type: String
      set: (v) ->
        if v != @description then @incImageVersion()
        return v
    }
    tags: [{
      type: String
      set: (v) ->
        return v.replace(/[^-\w\s]/g, '').trim()
    }]
    created: Date
    modified: Date
    drawing:
      type: [Schema.Types.Mixed]
      set: (v) ->
        unless (not v) or _.isEqual(v, @drawing) then @incImageVersion()
        return v
  IdeaSchema.pre 'save', (next) ->
    # Update timestamps
    unless @created
      @set 'created', new Date().getTime()
    @set 'modified', new Date().getTime()
    next()
  IdeaSchema.pre 'save', (next) ->
    # Save photos.
    if @photoData
      @photoVersion = (@get("photoVersion") or 0) + 1
      thumbnails.photoThumbs this, @photoData, (err) =>
        if err?
          next(new Error(err))
        else
          delete @photoData
          @incImageVersion()
          next(null)
    else
      next(null)
  IdeaSchema.pre 'save', (next) ->
    # Assemble drawings and thumbnails.
    if @_updateThumbnails
      delete @_updateThumbnails
      unless @background
        next(new Error("Can't draw drawing without background"))
      else
        thumbnails.drawingThumbs this, (err) ->
          if err?
            next(new Error(err))
          else
            next(null)
    else
      next(null)
  IdeaSchema.pre 'remove', (next) ->
    thumbnails.remove this, (err) ->
      if err?
        next(new Error(err))
      else
        next(null)
  IdeaSchema.virtual('photoURLs').get ->
      photos = {}
      if @photoVersion?
        for size in ["small", "medium", "large", "full"]
          photos[size] = "/uploads/dotstorm/idea/#{@id}/photo/#{size}#{@photoVersion}.png"
      return photos
  IdeaSchema.virtual('drawingURLs').get ->
      thumbs = {}
      if @imageVersion?
        for size in ["small", "medium", "large", "full"]
          thumbs[size] = "/uploads/dotstorm/idea/#{@id}/drawing/#{size}#{@imageVersion}.png"
      return thumbs
  IdeaSchema.virtual('taglist').get(
    -> return @tags.join(", ")
  ).set(
    (taglist) -> @set 'tags', taglist.split(/,\s*/)
  )
  IdeaSchema.methods.incImageVersion = ->
    @set "imageVersion", (@imageVersion or 0) + 1
  IdeaSchema.methods.DIMS = { x: 600, y: 600 }
  IdeaSchema.methods.getDrawingPath = (size) ->
    if @drawingURLs[size]?
      return thumbnails.UPLOAD_PATH + @drawingURLs[size]
    return null
  IdeaSchema.methods.getPhotoPath = (size) ->
    if @photoURLs[size]?
      return thumbnails.UPLOAD_PATH + @photoURLs[size]
    return null
  IdeaSchema.methods.serialize = ->
    json = @toJSON()
    json.drawingURLs = @drawingURLs
    json.photoURLs = @photoURLs
    json.taglist = @taglist
    return json

  IdeaSchema.statics.findOneLight = (constraint, cb) ->
    return @findOne constraint, { "drawing": 0 }, cb
  IdeaSchema.statics.findLight = (constraint, cb) ->
    return @find constraint, { "drawing": 0 }, cb

  #
  # Dotstorms
  #

  # Idea Group: for sorting/ordering of ideas; embedded in dotstorm.
  IdeaGroupSchema = new Schema
    _id: { type: String }
    label: { type: String, trim: true }
    ideas: [{type: Schema.ObjectId, ref: 'Idea'}]

  # Dotstorm
  DotstormSchema = new Schema
    slug:
      type: String
      required: true
      unique: true
      trim: true
      match: /[-a-zA-Z0-9]+/
    embed_slug: {type: String, required: true, default: uuid.v4}
    name: { type: String, required: false, trim: true }
    topic: { type: String, required: false, trim: true }
    groups: [IdeaGroupSchema]
    trash: [{type: Schema.ObjectId, ref: 'Idea'}]
    sharing: {
      group_id: String
      public_view_until: Date
      public_edit_until: Date
      extra_viewers: [String]
      extra_editors: [String]
      advertise: Boolean
    }
  DotstormSchema.virtual('url').get = ->
    return "/d/#{@slug}"
  DotstormSchema.virtual('absolute_url').get = ->
    return "#{config.apps.dotstorm.url}#{@url}"
  DotstormSchema.methods.serialize = -> return @toJSON()
  DotstormSchema.methods.exportJSON = ->
    out = {
      slug: @slug
      embed_slug: @embed_slug
      name: @name
      topic: @topic
      url: @absolute_url
      groups: []
    }
    for group in @groups
      out.groups.push({
        label: group.label or ""
        ideas: ({
          description: idea.description
          hasDrawing: idea.drawing?.length > 0
          hasPhoto: idea.photoVersion > 0
          urls: {
            small: config.api_url + idea.drawingURLs.small
            medium: config.api_url + idea.drawingURLs.medium
            large: config.api_url + idea.drawingURLs.large
          }
          tags: (t for t in idea.tags or [])
          background: idea.background
          votes: idea.votes
        } for idea in group.ideas)
      })
    return out
  DotstormSchema.methods.exportRows = ->
    out = [[
        "description"
        "votes",
        "group label",
        "tags",
        "url",
        "has photo?",
        "has drawing?",
    ]]
    for group in @groups
      for idea in group.ideas
        out.push([
          idea.description or ""
          idea.votes or 0,
          group.label or "",
          idea.tags?.join(", ") or "",
          config.api_url + idea.drawingURLs.large,
          if idea.photoVersion > 0 then "yes" else "no",
          if idea.drawing?.length > 0 then "yes" else "no",
        ])
    return out

  DotstormSchema.statics.withLightIdeas = (constraint, cb) ->
    return schemas.Dotstorm.findOne(constraint).populate(
      'groups.ideas', { 'drawing': 0 }
    ).exec cb

  schemas = {}
  for name, schema of {Dotstorm: DotstormSchema, Idea: IdeaSchema, IdeaGroup: IdeaGroupSchema}
    try
      schemas[name] = mongoose.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)

  return schemas

module.exports = { load }
