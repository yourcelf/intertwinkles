mongoose  = require 'mongoose'
Schema    = mongoose.Schema
_         = require 'underscore'
icons     = require './icons'
carriers  = require './carriers'

schema = null

load = (config) ->
  absolute_url = ->
    ###
    We reuse a pattern in several models of having an 'application' property
    that refers to the key of a configured application, and a 'url' property
    that refers to an entity within that application.

    To get to the absolute URL for an entity, we must prefix it with the URL
    for its application.  This way, applications can live on the local server,
    or another server, and the data is portable if the application changes
    location.

    Example:
      application: firestarter
      application URL: http://localhost/firestarter/

      The firestarter with full URL "http://localhost/firestarter/f/slug" will
      thus have @url: "/f/slug"
    
    This method encodes that logic to build a virtual "absolute_url" property
    for each entity.
    ###
    if config.apps[@application]?.url?
      return config.apps[@application].url + @url
    return null


  UserSchema = new Schema {
    name: String
    joined: Date
    email: {type: String, unique: true, required: true}
    email_change_request: String
    mobile: {
      number: {type: String, match: /^[0-9]{10,14}$/}
      carrier: {
        type: String, validate: (val) -> return (not val?) or carriers[val]?
      }
    }
    icon: {
      pk: String # "primary key"; index to assets/img/source_icons/
      name: String
      color: {type: String, match: /[0-9A-F]{6}/i}
      sizes: {
        "16": String
        "32": String
        "64": String
      }
    }
    notifications: {
      activity_summaries: {
        sms:   {type: Boolean, default: false}
        email: {type: Boolean, default: true}
      }
      invitation: {
        sms:   {type: Boolean, default: false}
        email: {type: Boolean, default: true}
      }
      needs_my_response: {
        sms:   {type: Boolean, default: false}
        email: {type: Boolean, default: true}
      }
      group_members_changed: {
        sms:   {type: Boolean, default: false}
        email: {type: Boolean, default: true}
      }
    }
  }
  UserSchema.virtual('sms_address').get ->
    if @mobile.carrier? and @mobile.number?
      return carriers[@mobile.carrier].sms.replace("{number}", @mobile.number)
    return null
  UserSchema.virtual('icon.tiny').get ->
    "#{config.api_url}/uploads/#{@icon.sizes["16"]}"
  UserSchema.virtual('icon.small').get ->
    "#{config.api_url}/uploads/#{@icon.sizes["32"]}"
  UserSchema.virtual('icon.medium').get ->
    "#{config.api_url}/uploads/#{@icon.sizes["64"]}"
  UserSchema.virtual('icon.large').get ->
    "#{config.api_url}/uploads/#{@icon.sizes["64"]}"
  UserSchema.path('mobile.number').validate (val) ->
    # Ensure that both exist, or neither.
    return @mobile?.carrier? == @mobile?.number?
  UserSchema.pre "validate", (next) ->
    @icon.color = @icon.color.toUpperCase() if @icon?.color?
    next()
  UserSchema.pre 'validate', (next) ->
    if @mobile.number
      @mobile.number = @mobile.number.replace(/[^0-9]/g, "")
    next()
  UserSchema.pre "save", (next) ->
    if not @icon?.pk? or not @icon?.color?
      icons.get_random_icon (err, icon) =>
        throw err if err?
        @icon = icon
        next()
    else if @isModified("icon") or not (
            @icon.sizes["16"] and @icon.sizes["32"] and @icon.sizes["64"])
      icons.render_icon @icon.pk, @icon.color, (err, icon) =>
        throw err if err?
        @icon = icon
        next()
    else
      next()
  UserSchema.set('toObject', {virtuals: true})
  UserSchema.options.toObject.transform = (doc, ret, options) ->
    delete ret.icon.sizes
    delete ret.mobile
    return ret
  UserSchema.set('toJSON', {virtuals: true})
  UserSchema.options.toJSON.transform = (doc, ret, options) ->
    delete ret.icon.sizes
    delete ret.mobile
    return ret

  membership_fields = {
    invited_by: {type: Schema.ObjectId, ref: 'User'}
    invited_on: Date
    role: String
    voting: Boolean
    user: {type: Schema.ObjectId, ref: 'User', required: true}
  }
  GroupSchema = new Schema {
    created: Date
    modified: Date
    members: [_.extend({
      joined: Date
    }, membership_fields)]
    invited_members: [_.extend({
      invitation_sent: Date
    }, membership_fields)]
    past_members: [_.extend({
      removed_by: {type: Schema.ObjectId, ref: 'User'}
      joined: Date
      left: Date
    }, membership_fields)]
    name: {type: String, required: true}
    slug: {type: String, required: true, unique: true}
    disabled: Boolean
    logo: {
      full: String
      thumb: String
    }
  }
  GroupSchema.pre "save", (next) ->
    if not @created?
      @created = new Date()
    next()
  GroupSchema.virtual('logo.large').get ->
    if @logo.full?
      return "#{config.api_url}/uploads/#{@logo.full}"
    return null
  GroupSchema.virtual('logo.small').get ->
    if @logo.thumb?
      return "#{config.api_url}/uploads/#{@logo.thumb}"
    return null
  GroupSchema.virtual('url').get ->
    return "/groups/show/#{@slug}/"
  GroupSchema.virtual('absolute_url').get ->
    return config.apps.www.url + @url
  GroupSchema.set('toObject', {virtuals: true})
  GroupSchema.options.toObject.transform = (doc, ret, options) ->
    delete ret.logo?.full
    delete ret.logo?.thumb
    return ret
  GroupSchema.set('toJSON', {virtuals: true})
  GroupSchema.options.toJSON.transform = (doc, ret, options) ->
    delete ret.logo?.full
    delete ret.logo?.thumb
    return ret

  EventSchema = new Schema {
    application: String
    entity: String
    type: String
    url: String
    date: Date
    # Identity: one of anon_id or user
    anon_id: String
    user: {type: Schema.ObjectId, ref: 'User'}
    via_user: {type: Schema.ObjectId, ref: 'User'}
    group: {type: Schema.ObjectId, ref: 'Group'}
    data: {type: Schema.Types.Mixed}
  }
  EventSchema.virtual("verbed").get ->
    return {
      visit: "visited"
      trim: "deleted content from"
      append: "added to"
      create: "created"
      update: "updated"
      join: "joined"
      decline: "declined"
      vote: "voted"
    }[@type] or @type + "ed"
  EventSchema.virtual("absolute_url").get(absolute_url)
  EventSchema.virtual("title").get ->
    return (
      @data?.title or
      config.apps[@application]?.name or
      @application
    )
  EventSchema.pre "save", (next) ->
    if not @date?
      @date = new Date()
    next()
  EventSchema.set('toObject', {virtuals: true})
  EventSchema.set('toJSON', {virtuals: true})

  NotificationSchema = new Schema {
    application: String # Application label, if any
    entity: String      # Object ID or other identifier of notice event, if any
    type: String        # Type of notification (e.g. twinkle, invitation, etc)
    recipient: {type: Schema.ObjectId, ref: 'User', required: true}
    sender: {type: Schema.ObjectId, ref: 'User'} # User causing notification, if any

    url: String         # To where should this notification resolve when clicked?
    date: Date          # When was this notification made?
    formats: {
      web: String       # For display in lists of notifications on the web
      sms: String       # For display in text messages
      email: {          # For display in emails
        subject: String
        text: String
        html: String
      }
    }
    sent: {
      sms: Date
      email: Date
    }
    cleared: {type: Boolean} # Has this been read?
    suppressed: {type: Boolean}
  }
  NotificationSchema.pre "save", (next) ->
    @cleared = false if not @cleared?
    @suppressed = false if not @suppressed?
    @date = new Date() if not @date?
    next()
  NotificationSchema.static 'findSendable', (constraint, callback) ->
    # No notifications older than 1 day.
    one_day = 1000 * 60 * 60 * 24
    from_date = new Date(new Date().getTime() - one_day)
    @find(_.extend({
      $or: [
        {"sent.email": null, "formats.email": {$exists: true}}
        {"sent.sms":   null, "formats.sms":   {$exists: true}}
      ],
      cleared: {$ne: true}
      suppressed: {$ne: true}
      date: {$gte: from_date}
    }, constraint)).populate("recipient").exec(callback)
  NotificationSchema.virtual('absolute_url').get(absolute_url)
  NotificationSchema.set('toObject', {virtuals: true})
  NotificationSchema.set('toJSON', {virtuals: true})

  SearchIndexSchema = new Schema {
    application: {type: String, required: true}
    entity: {type: String, required: true}
    type: {type: String, required: true}
    url: {type: String, required: true}
    title: {type: String, required: true}
    summary: {type: String, required: true}
    modified: Date

    text: {type: String, required: true}

    sharing: {
      group_id: String
      public_view_until: Date
      public_edit_until: Date
      extra_viewers: [String]
      extra_editors: [String]
      advertise: Boolean
    }
  }
  SearchIndexSchema.virtual('absolute_url').get(absolute_url)
  SearchIndexSchema.pre "save", (next) ->
    @modified = new Date()
    next()
  SearchIndexSchema.set('toObject', {virtuals: true})
  SearchIndexSchema.set('toJSON', {virtuals: true})


  #
  # Twinkles
  #

  TwinkleSchema = new Schema {
    application: {type: String, required: true}
    entity: {type: String, required: true}
    subentity: {type: String, required: false}
    url: {type: String, required: true}
    sender_anon_id: String
    sender: {type: Schema.ObjectId, ref: 'User', required: false}
    recipient: {type: Schema.ObjectId, ref: 'User', required: false}
    date: Date
  }
  TwinkleSchema.virtual('absolute_url').get(absolute_url)
  TwinkleSchema.pre "save", (next) ->
    @date = new Date() unless @date?
  TwinkleSchema.set('toObject', {virtuals: true})
  TwinkleSchema.set('toJSON', {virtuals: true})

  #
  # Short URLs
  #

  SHORT_URL_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIKLMNOPQRSTUVWXYZ0123456789"
  SHORT_PATH_LENGTH = 4

  ShortURLSchema = new Schema {
    application: {type: String, required: true}
    long_path: {type: String, required: true}
    short_path: {type: String, unique: true}
  }
  ShortURLSchema.virtual("absolute_short_url").get ->
    return config.short_url_base + @short_path
  ShortURLSchema.virtual("absolute_long_url").get ->
    if config.apps[@application]?.url?
      return config.apps[@application].url + @long_path
    return null
  ShortURLSchema.pre "save", (next) ->
    return next() if @short_path?
    get_unique_short_path (err, short_path) =>
      return next(err) if err?
      @short_path = short_path
      next()
  ShortURLSchema.set('toObject', {virtuals: true})
  ShortURLSchema.set('toJSON', {virtuals: true})

  schemas = {}
  for name, schema of {
        User: UserSchema, Group: GroupSchema, Event: EventSchema,
        Notification: NotificationSchema, SearchIndex: SearchIndexSchema,
        Twinkle: TwinkleSchema, ShortURL: ShortURLSchema}
    try
      schemas[name] = mongoose.connection.model(name)
    catch e
      schemas[name] = mongoose.model(name, schema)

  get_unique_short_path = (callback) =>
    short_path = (SHORT_URL_CHARS.charAt(parseInt(Math.random() * SHORT_URL_CHARS.length)) for i in [0...SHORT_PATH_LENGTH]).join("")
    schemas.ShortURL.findOne {short_path}, (err, doc) =>
      return callback(err) if err?
      if not doc?
        return callback(null, short_path)
      else
        get_unique_short_path(callback)

  return schemas

module.exports = { load }
