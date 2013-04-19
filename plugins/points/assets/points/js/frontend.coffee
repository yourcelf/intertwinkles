###########################################################
# Model
############################################################

class PointsModel extends Backbone.Model
  idAttribute: "_id"

  addHandlers: =>
    @listenTo intertwinkles.socket, "points:pointset", @_load
    @listenTo intertwinkles.socket, "points:point", @_pointSet
    @listenTo intertwinkles.socket, "points:support", @_supportSet
    @listenTo intertwinkles.socket, "points:editing", @_editingSet
    @listenTo intertwinkles.socket, "points:approved", @_approvedSet
    @listenTo intertwinkles.socket, "points:move", @_pointMoved

  removeHandlers: =>
    @stopListening intertwinkles.socket, "points:pointset", @_load
    @stopListening intertwinkles.socket, "points:point", @_pointSet
    @stopListening intertwinkles.socket, "points:support", @_supportSet
    @stopListening intertwinkles.socket, "points:editing", @_editingSet
    @stopListening intertwinkles.socket, "points:approved", @_approvedSet
    @stopListening intertwinkles.socket, "points:move", @_pointMoved

  _load: (data) => @set data.model

  getPoint: (point_id) =>
    return _.find(@get("points"), (p) -> p._id == point_id) or
           _.find(@get("drafts"), (p) -> p._id == point_id)

  getListPos: (point_id) =>
    for list in [@get("points"), @get("drafts")]
      for point, i in list
        if point._id == point_id
          return [list, i]
    return null

  isApproved: (point_id) =>
    list_i = @getListPos(point_id)
    return false unless list_i?
    [list, i] = list_i
    return list == @get("points")

  _matchSupporter: (data, supporter) =>
    d = data
    s = supporter
    return (
      (s.user_id? and d.user_id? and s.user_id == d.user_id) or
      (not s.user_id and not data.user_id and
       s.name and d.name and s.name == d.name)
    )

  isSupporter: (data, point) =>
    for supporter in point.revisions[0].supporters
      return true if @_matchSupporter(supporter, data)
    return false


  isSoleSupporter: (point) =>
    me = {user_id: intertwinkles.user.id, name: intertwinkles.user.get("name")}
    return point.revisions[0].supporters.length == 1 and (
      @_matchSupporter(point.revisions[0].supporters[0], me)
    )

  #
  # Add a new revision to a point, or create a new point with the given text.
  #
  revisePoint: (data, callback) =>
    # Await callback, as this is not an idempotent call.
    intertwinkles.socket.once "points:point", callback
    intertwinkles.socket.send "points/revise_point", {
      _id: @id
      text: data.text
      point_id: data.point_id
      user_id: data.user_id
      name: data.name
    }
  # Socket push to set a point.
  _pointSet: (data) =>
    point = @getPoint(data.point._id)
    if point?
      _.extend(point, data.point)
      @trigger "change:point:#{point._id}", point
      @trigger "notify:point:#{point._id}", point
    else
      @get("drafts").unshift(data.point)
      @trigger "change:drafts"
      @trigger "notify:point:#{data.point._id}", data.point

  #
  # Change your vote for a point
  #
  setSupport: (data, callback) =>
    # Display immediately, then send socket. Response will be idempotent.
    @_supportSet(data)
    intertwinkles.socket.once "points:support", callback
    intertwinkles.socket.send "points/support_point", _.extend({
      _id: @id
    }, data)

  # Socket push for changed votes.
  _supportSet: (data) =>
    point = @getPoint(data.point_id)
    return @fetch() unless point?
    if data.vote
      if not _.find(point.revisions[0].supporters, (s) => @_matchSupporter(data, s))
        point.revisions[0].supporters.push({
          user_id: data.user_id
          name: data.name
        })
        @trigger "change:point:#{point._id}"
    else
      point.revisions[0].supporters = _.reject(
        point.revisions[0].supporters,
        (s) => @_matchSupporter(data, s)
      )
      @trigger "change:point:#{point._id}"
    @trigger "notify:supporter:#{point._id}", data

  #
  # Set whether we are editing a point.
  #
  setEditing: (data, callback) =>
    intertwinkles.socket.once "points:editing", callback
    intertwinkles.socket.send "points/set_editing", _.extend({
      _id: @id
    }, data)

  _editingSet: (data) =>
    point = @getPoint(data.point_id)
    return @fetch() unless point?
    point.editing = data.editing
    @trigger "change:point:#{point._id}"

  #
  # Set whether or not a point is approved
  #
  setApproved: (data, callback) =>
    # Display immediately, then send socket. Response will be idempotent.
    @_approvedSet(data)
    intertwinkles.socket.once "points:approved", callback
    intertwinkles.socket.send "points/set_approved", _.extend({
      _id: @id,
    }, data)

  # Socket push approval of point
  _approvedSet: (data) =>
    try
      [list, pos] = @getListPos(data.point_id)
    catch e
      return @fetch()
    if list == @get("drafts") == data.approved
      # We're inconsistent -- we got a message to move something to where it
      # already is.
      console.debug("Inconsistent", data, this)
      return @fetch()
    [point] = list.splice(pos, 1)
    if data.approved
      @get("points").push(point)
    else
      @get("drafts").unshift(point)
    @trigger "change:points"
    @trigger "change:drafts"
    @trigger "notify:point:#{data.point_id}"

  #
  # Move point
  #
  movePoint: (data, callback) =>
    # Wait for return, as this is not idempotent.
    intertwinkles.socket.once "points:move", callback
    intertwinkles.socket.send "points/move_point", _.extend({
      _id: @id,
    }, data)

  # Socket push move of point
  _pointMoved: (data) =>
    try
      [list, i] = @getListPos(data.point_id)
    catch e
      return @fetch()
    [point] = list.splice(i, 1)
    list.splice(data.position, 0, point)
    changed = if list == @get("drafts") then "drafts" else "points"
    @trigger "change:#{changed}"
    @trigger "notify:point:#{data.point_id}"

  #
  # Retrieve all data for this pointset.
  #
  fetch: (cb) =>
    return unless @get("slug")
    if cb?
      intertwinkles.socket.once "points:pointset", (data) =>
        @_load(data)
        cb(null, this)
    intertwinkles.socket.send "points/fetch_pointset", {slug: @get("slug")}

  #
  # Save changes to the name, slug, and sharing, but not points/drafts.
  #
  save: (update, opts) =>
    @set(update) if update?
    data = {
      model: {
        _id: @id
        name: @get("name")
        slug: @get("slug")
        sharing: @get("sharing")
      }
    }
    if opts.success? or opts.error?
      intertwinkles.socket.once "points:pointset", (data) =>
        opts.error(data.error) if data.error?
        opts.success(data.model) if data.model?
    intertwinkles.socket.send "points/save_pointset", data

fetchPointsList = (cb) =>
  intertwinkles.socket.once "points:list", cb
  intertwinkles.socket.send "points/fetch_pointset_list"

###########################################################
# Views
###########################################################

class PointsBaseView extends intertwinkles.BaseView
  events: 'click .softnav': 'softNav'
  initialize: (options={}) ->
    super()
    @model = options.model
  render: =>
    @$el.html(@template())

#
# Front matter
#

class SplashView extends PointsBaseView
  template:     _.template $("#splashTemplate").html()
  itemTemplate: _.template $("#splashItemTemplate").html()
  
  initialize: (options) ->
    super(options)
    @setPointsList(options.pointSetList, false)
    @listenTo intertwinkles.user, "change", @fetchPointsList

  fetchPointsList: => fetchPointsList(@setPointsList)

  setPointsList: (data, render=true) =>
    @pointSetList = {
      group: (new PointsModel(tp) for tp in data.group or [])
      public: (new PointsModel(tp) for tp in data.public or [])
    }
    if render
      @render()

  render: =>
    @$el.html(@template())
    if @pointSetList.group?.length > 0
      @$(".group-pointsets").html("<ul></ul>")
      for pointset in @pointSetList.group
        @_addItem(".group-pointsets ul", pointset)
    if @pointSetList.public?.length > 0
      @$(".public-pointsets").html("<ul></ul>")
      for pointset in @pointSetList.public
        @_addItem(".public-pointsets ul", pointset)
    intertwinkles.sub_vars(@el)

  _addItem: (selector, pointset) =>
    @$(selector).append(@itemTemplate(pointset: pointset))

#
# Edit or add a new board.
#
  
class EditPointSetView extends PointsBaseView
  template: _.template $("#editTemplate").html()
  events:
    'click .softnav': 'softNav'
    'submit    form': 'savePointSet'
    'keyup #id_name': 'setSlug'
    'keyup #id_slug': 'checkSlug'

  initialize: (options) ->
    super(options)
    if options?.model.id
      @model = options.model
      @title = "Edit Board Settings"
      @action = "Save"
    else
      @model = new PointsModel()
      @title = "Add new board"
      @action = "Add board"

  _slugCheck = (show) =>

  setSlug: =>
    unless @model.get("slug")
      @$("#id_slug").val(intertwinkles.slugify(@$("#id_name").val()))
    @checkSlug()

  checkSlug: =>
    val = @$("#id_slug").val()
    parent = @$("#id_slug").closest(".control-group")
    showURL = ->
      parent.find(".url-display").html(
        "#{INTERTWINKLES_APPS.points.url}/u/#{encodeURIComponent(val)}/"
      )
    if val and val != @model.get("slug")
      intertwinkles.socket.send "points/check_slug", {slug: val}
      intertwinkles.socket.once "points:check_slug", (data) =>
        parent.removeClass('error')
        parent.find(".error-msg").remove()
        if data.ok
          showURL()
        else
          parent.addClass('error')
          @$("#id_slug").after(
            "<span class='help-inline error-msg'>Name not available</span>"
          )
          parent.find(".url-display").html("")
    else if val == @model.get("slug")
      showURL()

  render: =>
    @$el.html(@template({
      model: @model.toJSON()
      title: @title
      action: @action
    }))
    @sharing_control?.remove()
    @sharing_control = new intertwinkles.SharingFormControl({
      sharing: @model.get("sharing")
    })
    @addView("#sharing_controls", @sharing_control)
  
  savePointSet: (event) =>
    event.preventDefault()
    cleaned_data = @validate()
    if cleaned_data
      @model.save {
        name: cleaned_data.name
        slug: cleaned_data.slug
        sharing: @sharing_control.sharing
      }, {
        success: (model) =>
          intertwinkles.app.navigate("/points/u/#{model.slug}/", {
            trigger: true
          })
      }

  validate: =>
    return @validateFields "form", [
      ["#id_name", ((val) -> $.trim(val) or null), "This field is required."]
      ["#id_slug", ((val) -> $.trim(val) or null), "This field is required."]
    ]

#
# Main view for a pointset. Display a single board with many points and drafts
# of points.
#

class PointSetView extends PointsBaseView
  template: _.template $("#pointsetTemplate").html()
  events:
    'click .softnav': 'softNav'
    'click a.add-point': 'addPoint'

  initialize: (options) ->
    super(options)
    @listenTo @model, "change:name", @render
    @listenTo @model, "change:points", @renderPoints
    @listenTo @model, "change:drafts", @renderDrafts
    @listenTo intertwinkles.socket, "points:events", @renderSummary

  addPoint: (event) =>
    event.preventDefault()
    form = new EditPointView(model: @model)
    form.render()

  render: =>
    @$el.html(@template(model: @model.toJSON()))
    @renderPoints()
    @renderDrafts()
    intertwinkles.socket.send "points/get_points_events", {_id: @model.id}

  _renderPointList: (list, dest) =>
    dest = $(dest)
    views = []
    dest.html("")
    for point,i in list
      view = new PointView({model: @model, point: point})
      dest.append($("<li></li>").html(view.el))
      view.render()
      view.on "startdrag", @startDrag
      views.push(view)
    if intertwinkles.can_edit(@model)
      $(dest).addClass("children-draggable")
    return views

  renderPoints: =>
    @pointviews = @_renderPointList(@model.get("points"), ".points")

  renderDrafts: =>
    @draftviews = @_renderPointList(@model.get("drafts"), ".drafts")

  renderSummary: (data) =>
    collection = intertwinkles.buildEventCollection(data.events)
    summary = new intertwinkles.EventsSummary({
      collection: collection.deduplicate()
      modificationWhitelist: ["visit", "vote"]
    })
    @$(".history-holder").html(summary.el)
    summary.render()


  _get_box: ($el) ->
    offset = $el.offset()
    w = $el.outerWidth(true)
    h = $el.outerHeight(true)
    return {
      x1: offset.left
      y1: offset.top
      x2: offset.left + w
      y2: offset.top + h
      w: w
      h: h
    }

  # Utility to calculate the x/y coordinates for the gap between two points,
  # which is the drop target.
  _drop_target_dims: (abovegap, belowgap, number, type) =>
    x1 = x2 = y1 = y2 = null
    targets = []
    if belowgap?
      $el = belowgap.$el
    else
      # Create a sentinel.
      @dragState.sentinel or= {}
      @dragState.sentinel[type]?.remove()
      @dragState.sentinel[type] = $("<div></div>")
      abovegap.$el.after(@dragState.sentinel[type])
      $el = @dragState.sentinel[type]
    if abovegap
      box = @_get_box(abovegap.$el)
      targets.push({
        # Add arbitrary padding below y2
        x1: box.x1, y1: box.y1 + box.h / 2, x2: box.x2, y2: box.y2 + 5,
        $el: $el, number: number, type: type
      })
    if belowgap
      box = @_get_box(belowgap.$el)
      targets.push({
        # Add arbitrary padding above y1.
        x1: box.x1, y1: box.y1 - 5, x2: box.x2, y2: box.y1 + box.h / 2 + 5,
        $el: $el, number: number, type: type
      })
    return targets

  #
  # Start dragging a point to reorder it.
  #

  startDrag: (pointview, event) =>
    event.preventDefault()
    return unless intertwinkles.can_edit(@model)
    # Calculate all the things!
    [list, number] = @model.getListPos(pointview.point._id)
    @dragState = {
      pointview: pointview
      startOffset: pointview.$el.offset()
      width: pointview.$el.width()
      height: pointview.$el.height()
      startX: event.clientX
      startY: event.clientY
      targets: []
      number: number
      type: if list == @model.get("points") then "points" else "drafts"
      listDims: {}
    }
    for type in ["drafts", "points"]
      el = @$("." + type)
      offset = el.offset()
      @dragState.listDims[type] = {
        x1: offset.left
        y1: offset.top
        x2: offset.left + el.width()
        y2: offset.top + el.height()
      }

    # Build a list of drag targets for all the points in our lists.
    for [list,type] in [[@pointviews, "points"], [@draftviews, "drafts"]]
      continue if list.length == 0
      unless @dragState.number == 0 and @dragState.type == type
        @dragState.targets = @dragState.targets.concat(
          @_drop_target_dims(null, list[0], 0, type))
      for abovegap, i in list
        number = i + 1
        if @dragState.type == type and i >= @dragState.number
          # If this is a movement within the same list, and we're moving
          # forward in the list, we need to decrement the number as we have
          # popped ourselves from the list.  If it's a foreign list we're being
          # teleported into, we don't need to do that.
          number -= 1
        continue if (number == @dragState.number and type == @dragState.type)
        if i < list.length - 1
          belowgap = list[i + 1]
        else
          belowgap = null
        @dragState.targets = @dragState.targets.concat(
          @_drop_target_dims(abovegap, belowgap, number, type))
      # final drop target is the space at the end of the list.  Only add a
      # target at the end of the list if we are not already at the end of that
      # list, and the list has space at its end.
      if @dragState.type != type or @dragState.number != list.length - 1
        {x1, y1, x2, y2} = @dragState.listDims[type]
        lastPoint = @dragState.targets[@dragState.targets.length - 1]
        # Does the list have space at the end? 20 is arbitrary padding here.
        if (x2 > lastPoint.x2 + 20) or (y2 > lastPoint.y2 + 20)
          # Bottom-right corner is easy: it's just the bottom-right of the
          # container.
          extra = {
            x2: x2, y2: y2, $el: lastPoint.$el,
            type: lastPoint.type, number: lastPoint.number
          }
          # Top left is trickier. Either:
          # 1. The top-right corner of lastPoint if the final column is unoccupied
          # 2. The bottom-left corner of lastPoint otherwise
          if lastPoint.x2 + 20 < x2
            # 1. Final column isn't occupied. Use top-right.
            extra.x1 = lastPoint.x2
            extra.y1 = lastPoint.y1
          else
            # 2. Final column is occupied. Use bottom-left.
            extra.x1 = lastPoint.x1
            extra.y1 = lastPoint.y2
          @dragState.targets.push(extra)

    # Build a clone of the point being dragged to render as the thing under our hands.
    @dragState.dragger = $("<div></div>").append(
      pointview.$el.clone()
    ).css({
      width: @dragState.width
      height: @dragState.height
      transform: "rotate(1deg)"
      position: "absolute"
      "background-image": $("body").css("background-image")
      left: @dragState.startOffset.left + "px"
      top: @dragState.startOffset.top + "px"
      "box-shadow": "0px 0px 10px #aaa"
      "user-select": "none"
      opacity: 0.9
      "z-index": 10000
    })
    # Show our clone.
    $("body").append(@dragState.dragger)
    # Hide the original, without reflowing.
    pointview.$el.css("opacity", 0)
    # Listen to mouse!
    $(window).on "mousemove", @continueDrag
    $(window).on "mouseup", @stopDrag

  continueDrag: (event) =>
    # Stop everything if we don't have a drag state.
    @stopDrag unless @dragState?
    # Update the position of the dragger.
    x = event.clientX
    y = event.clientY
    @dragState.dragger.css({
      left: @dragState.startOffset.left + (x - @dragState.startX) + "px"
      top: @dragState.startOffset.top + (y - @dragState.startY) + "px"
    })
    
    # Update the target as needed.
    for target in @dragState.targets
      if (target.x1 <= x < target.x2) and (target.y1 <= y < target.y2)
        return @_setTarget(target)
    @_clearTarget()

  _setTarget: (target) =>
    # If necessary, set a new drop target.
    return if (@dragState.target?.number == target.number and
               @dragState.target?.type == target.type)
    @_clearTarget()
    @dragState.placeholder = $("<div></div>").css({
      width: @dragState.width
      height: @dragState.height
      "-webkit-box-sizing": "border-box"
      "-moz-box-sizing": "border-box"
      "box-sizing": "border-box"
      border: "6px dashed #aaa"
      display: "none"
      "margin-top": "5px"
      "margin-bottom": "5px"
    }).slideDown(100)
    target.$el.before(@dragState.placeholder)
    @dragState.target = target

  _clearTarget: =>
    # Remove the drop target.
    # Re-show ourselves, so we take up space again.
    if @dragState?.placeholder or @dragState?.target
      @dragState.placeholder?.slideUp(100)
      delete @dragState?.target

  stopDrag: (event) =>
    $(window).off "mousemove", @continueDrag
    $(window).off "mouseup", @stopDrag
    $(".point").off "mouseover", @dragOver

    if @dragState.target?
      # Move points around.
      if @dragState.type != @dragState.target.type
        # We've changed types! Forbid moving to the position we'd start in.
        position = @dragState.target.number
        if (@dragState.target.type == "drafts" and position == 0) or (
            @dragState.target.type == "points" and
                          position == @model.get("points").length)
          # New drafts start at 0.
          position = null

        # Confirm that we want to change types.
        form = new ApprovePointView({
          model: @model, point: @dragState.pointview.point
        })
        form.render()
        form.on "done", =>
          # We do. Now rearrange, if we aren't forbidden.
          if position?
            @model.movePoint {point_id: form.point._id, position: position}
        form.on "canceled", =>
          @renderPoints()
          @renderDrafts()

      else
        # Moving within the same type.  Just set the position.
        @model.movePoint({
          point_id: @dragState.pointview.point._id
          position: @dragState.target.number
        })

      @dragState.placeholder.before(@dragState.dragger)
      @dragState.dragger.css({
        position: "relative"
        transform: "none"
        left: "0px"
        top: "0px"
        "z-index": "0"
      })
    else
      @dragState.pointview.$el.css("opacity", 1.0)
      @dragState.dragger.remove()

    for type, el of @dragState.sentinel or {}
      el.remove()
    @_clearTarget()
    @dragState = null

#
# Display a single point.
#

class PointView extends PointsBaseView
  template: _.template $("#pointTemplate").html()
  supportersTemplate: _.template $("#supportersTemplate").html()
  events:
    'click .softnav': 'softNav'
    'click .edit':    'edit'
    'click .mark-approved': 'approve'
    'click .upboat':  'vote'
    'mousedown .drag-handle': 'startDrag'

  initialize: (options) ->
    super(options)
    @point = options.point
    @listenTo @model, "change:point:#{@point._id}", @render
    @listenTo @model, "notify:point:#{@point._id}", @flash
    @listenTo @model, "notify:supporter:#{@point._id}", @flashSupporter
    @listenTo intertwinkles.user, "login", @render

  edit:    (event) =>
    event.preventDefault()
    form = new EditPointView({model: @model, point: @point })
    form.render()

  approve: (event) =>
    event.preventDefault()
    form = new ApprovePointView({model: @model, point: @point })
    form.render()

  vote: (event) =>
    event.preventDefault()
    form = new VoteView({model: @model, point: @point })
    form.render()

  flash: =>
    @$el.effect('highlight', {}, 5000)

  flashSupporter: (data) =>
    q = @$("[data-id=\"#{data.user_id or ""}\"][data-name=\"#{data.name or ""}\"]")
    q.addClass("added").effect('highlight', {}, 5000)

  startDrag: (event) =>
    @trigger('startdrag', this, event)

  render: =>
    [list, number] = @model.getListPos(@point._id)
    @$el.attr("data-id", @point._id)
    @$el.attr("data-number", number)
    approved = list == @model.get("points")
    @$el.addClass("point")
        .toggleClass("draft", not approved)
        .html(@template({
          model: @model.toJSON()
          point: @point
          approved: approved
          number: number
          sessionSupports: @model.isSupporter({
            user_id: intertwinkles.user.id, name: intertwinkles.user.get("name")
          }, @point)
          supportersTemplate: @supportersTemplate
        }))
    @$("[rel=popover]").popover()

class PointDetailView extends PointsBaseView
  template: _.template $("#pointDetailTemplate").html()
  initialize: (options) =>
    @model = options.model
    @point = @model.getPoint(options.point_id)
    @pointView = new PointView({model: @model, point: @point})
    @listenTo(intertwinkles.user, "login", @render)

  render: =>
    gid = @model.get("sharing")?.group_id
    group = intertwinkles.groups?[gid]
    @$el.html(@template({ model: @model.toJSON(), group: group }))
    @$(".point-detail-point").append(@pointView.el)
    @pointView.render()
    @$(".point.span6")

class HistoryView extends PointsBaseView
  template: _.template $("#historyTemplate").html()
  supportersTemplate: _.template $("#supportersTemplate").html()
  initialize: (options) ->
    @model = options.model
    @point = @model.getPoint(options.point_id)

  render: =>
    gid = @model.get("sharing")?.group_id
    group = intertwinkles.groups?[gid] or null
    @$el.html(@template({
      model: @model.toJSON()
      point: @point
      group: group
      supportersTemplate: @supportersTemplate
    }))
    intertwinkles.sub_vars(@el)
    @$("[rel=popover]").popover()

class VoteView extends intertwinkles.BaseModalFormView
  template: _.template $("#voteTemplate").html()
  events:
    'submit form': 'submit' # from super
    'change #id_user': 'updateAction'

  initialize: (options) ->
    @model = options.model
    @point = options.point
    super {
      context: {
        model: @model
        point: @point
      }
      validation: [
        ["#id_user_id", ((val) -> val or ""), ""]
        ["#id_user", ((val) -> $.trim(val) or null), "This field is required."]
      ]
    }

    @on "submitted", (cleaned_data) =>
      data = _.extend({point_id: @point?._id, vote: @canSupport}, cleaned_data)
      data.user_id = data.user_id or null
      @model.setSupport(data, @remove)

  updateAction: =>
    user_id = @$("#id_user_id").val()
    name = @$("#id_user").val()
    @canSupport = not @model.isSupporter({user_id, name}, @point)
    if @canSupport
      @$(".status").html("#{name} does not support this point yet.")
      @$(".btn-primary").html("<i class='icon-thumbs-up'></i> Add vote")
    else
      @$(".status").html("#{name} supports this point.")
      @$(".btn-primary").html("<i class='icon-thumbs-down'></i> Remove vote")
  
  render: =>
    super()
    user_choice = new intertwinkles.UserChoice(model: {
      user_id: intertwinkles.user.id
      name: intertwinkles.user.get("name")
    })
    @addView(".name-input", user_choice)
    @updateAction()

#
# Edit a point
#

class EditPointView extends intertwinkles.BaseModalFormView
  template: _.template $("#editPointTemplate").html()
  initialize: (options) ->
    @model = options.model
    @point = options.point
    super {
      context: {
        model: @model.toJSON()
        point: @point
        soleSupporter: (not @point) or @model.isSoleSupporter(@point)
      }
      validation: [
        ["#id_user_id", ((val) -> val or ""), ""]
        ["#id_user", ((val) -> $.trim(val) or null), "Please enter your name"]
        ["#id_text", ((val) -> $.trim(val) or null), "This field is required"]
      ]
    }
    if @point?
      @on "hidden", =>
        @model.setEditing({point_id: @point._id, editing: false})
        "setEditing on hidden"
        @remove() unless @removed

    @on "submitted", (cleaned_data) =>
      data = _.extend({point_id: @point?._id}, cleaned_data)
      @model.revisePoint(data, @remove)

  render: =>
    if @point?
      @model.setEditing({point_id: @point._id, editing: true})
    super()
    @addView(".name-input", new intertwinkles.UserChoice(model: {
      user_id: intertwinkles.user.id
      name: intertwinkles.user.get("name")
    }))

class ApprovePointView extends intertwinkles.BaseModalFormView
  template: _.template $("#approvePointTemplate").html()
  initialize: (options) ->
    @model = options.model
    @point = options.point
    @approved = @model.isApproved(@point._id)

    super {
      context: {
        model: @model.toJSON()
        point: @point
        approved: @approved
      }
      validation: []
    }
    @on "hidden", =>
      @remove() unless @removed
      @trigger "canceled" unless @notCanceled

    @on "submitted", (cleaned_data) =>
      @notCanceled = true
      @model.setApproved({ point_id: @point._id, approved: not @approved }, =>
        @trigger "done"
      )
      @remove()


###########################################################
# Router
###########################################################

class Router extends Backbone.Router
  routes:
    "points/u/:slug/point/:point_id/": "pointDetail"
    "points/u/:slug/history/:point_id/": "history"
    "points/u/:slug/edit/": "edit"
    "points/u/:slug/": "board"
    "points/add/": "add"
    "points/": "index"

  initialize: ->
    @model = new PointsModel()
    @model.addHandlers()
    @model.set(INITIAL_DATA.pointset or {})
    @pointSetList = INITIAL_DATA.pointsets_list
    @_joinRoom(@model) if @model.id?
    @listenTo @model, "change:_id", =>
      if @model.id? then @_joinRoom(@model) else @_leaveRoom()
    super()

  pointDetail: (slug, point_id) =>
    $("title").html(@model.get("name") + " - Points of Unity")
    @_open(
      new PointDetailView({model: @model, point_id: point_id}), slug
    )
  history: (slug, point_id) =>
    $("title").html(@model.get("name") + " - Points of Unity")
    @_open(
      new HistoryView({model: @model, point_id: point_id}), slug
    )
  edit: (slug) =>
    $("title").html("Edit " + @model.get("name") + " - Points of Unity")
    @_open(new EditPointSetView({model: @model}), slug)
  board: (slug) =>
    $("title").html(@model.get("name") + " - Points of Unity")
    @_open(new PointSetView({model: @model}), slug)
  add: =>
    $("title").html("Add - Points of Unity")
    @_open(new EditPointSetView({model: @model}), null)
  index: =>
    $("title").html("Points of Unity")
    view = new SplashView(pointSetList: @pointSetList)
    if @view?
      fetchPointsList(view.setPointsList)
    @_open(view, null)

  onReconnect: =>
    @model.fetch()
    @_joinRoom(@model)

  _open: (view, slug) =>
    if @model.get("slug") and @model.get("slug") != slug
      @_leaveRoom()
    if slug? and not @model.get("slug")?
      @model.set({slug: slug})
      return @model.fetch =>
        $("title").html(@model.get("name") + " - Points of Unity")
        @_joinRoom(@model)
        @_showView(view)
    else
      @_showView(view)

  _showView: (view) =>
    @view?.remove()
    $("#app").html(view.el)
    view.render()
    @view = view
    window.scrollTo(0, 0)

  _leaveRoom: =>
    @roomView?.$el.before("<li class='room-users'></li>")
    @roomView?.remove()
    @sharingView?.remove()

  _joinRoom: =>
    @_leaveRoom()

    @roomView = new intertwinkles.RoomUsersMenu(room: "points/#{@model.id}")
    $(".sharing-online-group .room-users").replaceWith(@roomView.el)
    @roomView.render()

    @sharingView = new intertwinkles.SharingSettingsButton(model: @model)
    $(".sharing-online-group .sharing").html(@sharingView.el)
    @sharingView.render()
    @sharingView.on "save", (sharing) =>
      @model.save {sharing}, {success: => @sharingView.close()}

###########################################################
# Main
###########################################################

app = null
intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "points"})
  intertwinkles.build_footer($("footer"))

  unless app?
    app = intertwinkles.app = new Router()
    Backbone.history.start({pushState: true, hashChange: false})
    intertwinkles.socket.on "reconnect", ->
      intertwinkles.socket.once "identified", ->
        app.onReconnect()
