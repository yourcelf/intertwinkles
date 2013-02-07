mongoose  = require 'mongoose'
Schema    = mongoose.Schema
_         = require 'underscore'
icons     = require './icons'
carriers  = require './carriers'

load = (config) ->
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
      pk: String
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
    "#{config.api_url}/static/#{@icon.sizes["16"]}"
  UserSchema.virtual('icon.small').get ->
    "#{config.api_url}/static/#{@icon.sizes["32"]}"
  UserSchema.virtual('icon.medium').get ->
    "#{config.api_url}/static/#{@icon.sizes["64"]}"
  UserSchema.virtual('icon.large').get ->
    "#{config.api_url}/static/#{@icon.sizes["64"]}"
  UserSchema.path('mobile.number').validate (val) ->
    # Ensure that both exist, or neither.
    return @mobile?.carrier? == @mobile?.number?
  UserSchema.pre "validate", (next) ->
    @icon.color = @icon.color.toUpperCase() if @icon?.color?
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
  User = mongoose.model("User", UserSchema)

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
      return "#{config.api_url}/static/#{@logo.full}"
    return null
  GroupSchema.virtual('logo.small').get ->
    if @logo.thumb?
      return "#{config.api_url}/static/#{@logo.thumb}"
    return null
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
  Group = mongoose.model("Group", GroupSchema)

  EventSchema = new Schema {
    application: String
    entity: String
    type: String
    entity_url: String
    date: Date
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
    }[@type] or @type + "ed"
  EventSchema.virtual("absolute_url").get ->
    if config.apps[@application]?.url?
      return config.apps[@application].url + @entity_url
    return null
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
  Event = mongoose.model("Event", EventSchema)

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
    @find(_.extend({
      $or: [
        {"sent.email": null, "formats.email": {$exists: true}}
        {"sent.sms":   null, "formats.sms":   {$exists: true}}
      ],
      cleared: {$ne: true}
      suppressed: {$ne: true}
    }, constraint)).populate("recipient").exec(callback)

  Notification = mongoose.model("Notification", NotificationSchema)

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
  SearchIndexSchema.virtual('absolute_url').get ->
    if config.apps[@application]?.url?
      config.apps[@application].url + @url
    else
      null
  SearchIndexSchema.pre "save", (next) ->
    @modified = new Date()
    next()
  SearchIndex = mongoose.model("SearchIndex", SearchIndexSchema)

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
  TwinkleSchema.pre "save", (next) ->
    @date = new Date() unless @date?
  Twinkle = mongoose.model("Twinkle", TwinkleSchema)

  #
  # Short URLs
  #

  SHORT_URL_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIKLMNOPQRSTUVWXYZ0123456789"
  SHORT_PATH_LENGTH = 4

  get_unique_short_path = (callback) =>
    short_path = (SHORT_URL_CHARS.charAt(parseInt(Math.random() * SHORT_URL_CHARS.length)) for i in [0...SHORT_PATH_LENGTH]).join("")
    ShortURL.findOne {short_path}, (err, doc) =>
      return callback(err) if err?
      if not doc?
        return callback(null, short_path)
      else
        get_unique_short_path(callback)

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
  ShortURL = mongoose.model("ShortURL", ShortURLSchema)

  return { User, Group, Event, Notification, SearchIndex, Twinkle, ShortURL }

module.exports = { load }
