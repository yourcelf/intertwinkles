twinkle_template = "
  <img src='/static/img/twinkle_<%- active ? '' : 'in' %>active-32.png'
       alt='Twinkle (<%- active ? '' : 'in' %>active)' />
  <%- count > 0 ? count : '' %>
"
class Twinkle extends Backbone.Model
  idAttribute: '_id'
class TwinkleCollection extends Backbone.Collection
  model: Twinkle

#
# Create twinkle views for all the .twinkles elements in the scope 'scope'.
# Returns a map of twinkle views.  For efficiency, when re-rendering, pass
# the returned view map back as `old_view_map`, to recycle them, saving
# some socket traffic to populate the twinkles.
#
intertwinkles.twinklify = (prefix, scope, old_view_map) ->
  old_view_map or= {}
  current_view_keys = []
  new_view_map = {}
  fetch_entities = {}
  $(".twinkles", scope or "document").each ->
    $el = $(this)
    attrs = {
      application: $el.attr("data-application")
      entity: $el.attr("data-entity")
      subentity: $el.attr("data-subentity")
      recipient: $el.attr("data-recipient")
      url: $el.attr("data-url")
      prefix: prefix
    }
    hash = [attrs.application, attrs.entity,
      attrs.subentity, attrs.recipient, attrs.url].join(":")
    current_view_keys.push(hash)

    if old_view_map[hash]
      $el.replaceWith(old_view_map[hash].el).show()
      old_view_map[hash].render()
    else
      view = new TwinkleView(attrs)
      view.render()
      $el.replaceWith(view.el)
      new_view_map[hash] = view
      fetch_entities[view.attrs.application + ":" + view.attrs.entity] = {
        application: view.attrs.application
        entity: view.attrs.entity
      }

  # Fetch twinkles for new entities.
  for hash, entity of fetch_entities
    intertwinkles.socket.send "#{prefix}/get_twinkles", entity

  for hash in _.difference(_.keys(old_view_map), current_view_keys)
    old_view_map[hash].remove()
    delete old_view_map[hash]

  return _.extend old_view_map, new_view_map

class TwinkleView extends intertwinkles.BaseView
  template: _.template(twinkle_template)
  events: _.extend {
    'click': 'toggleTwinkle'
  }, intertwinkles.BaseEvents

  initialize: (options) ->
    @collection = options.twinkles or new TwinkleCollection()
    @prefix = options.prefix
    @attrs = {
      application: options.application
      entity: options.entity
      subentity: options.subentity
      recipient: options.recipient or null
      url: options.url or window.location.pathname
    }
    intertwinkles.socket.on "twinkles", @parseTwinkles
    super()

  fetch: =>
    intertwinkles.socket.send "#{@prefix}/get_twinkles", @attrs

  remove: =>
    intertwinkles.socket.off "twinkles", @parseTwinkles
    super()

  render: =>
    @loading = false
    @$el.html(@template({count: @collection.length, active: @isActive()}))
        .addClass("twinkle-controls")

    # Popover
    unless @secondRender
      @$el.popover {
        title: =>
          if @collection.length > 0 then "Twinkled by:" else "Twinkles:"
        content: =>
          if @collection.length > 0
            return (@renderUser(model.get("sender")) for model in @collection.models).join(", ")
          else
            return "No twinkles yet. Click to twinkle."
        placement: "top"
        trigger: "hover"
        html: true
      }
      @secondRender = true

  parseTwinkles: (data) =>
    render = false
    if data.remove?
      removal = @collection.get(data.remove)
      if removal?
        @collection.remove(removal)
        render = true
    for twinkle in data.twinkles or []
      match = true
      for attr, val of @attrs
        if twinkle[attr] != val
          match = false
          break
      unless match
        continue
      render = true
      existing = @collection.get(twinkle._id)
      if existing?
        existing.set(twinkle)
      else
        @collection.add(new Twinkle(twinkle))
    @render() if render

  getActive: => _.find(@collection.models, (m) -> (
      (m.get("sender") == intertwinkles.user.id) or
      (m.get("sender") == null and m.get("sender_anon_id") == INITIAL_DATA.anon_id)
    ))

  isActive: =>
    @getActive()?

  toggleTwinkle: (event) =>
    unless @loading
      active = @getActive()
      if active?
        intertwinkles.socket.send "#{@prefix}/remove_twinkle", {
          twinkle_id: active.id
          entity: @attrs.entity
        }
        @collection.remove active
        @render()
      else
        intertwinkles.socket.send "#{@prefix}/post_twinkle", @attrs
        @loading = true
        @$("img").attr("src", "/static/img/spinner.gif")
    return false
