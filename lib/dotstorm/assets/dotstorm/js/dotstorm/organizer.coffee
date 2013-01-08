getPx = (el, v) -> return parseInt(el.css(v).replace("px", ""))

class ds.Organizer extends Backbone.View
  #
  # Display a list of ideas, and provide UI for grouping them via
  # drag and drop.
  #
  template: _.template $("#dotstormOrganizer").html() or ""
  events:
    'click         .add-link': 'softNav'
    'touchend      .add-link': 'softNav'
    'click              .tag': 'toggleTag'
    'touchend           .tag': 'toggleTag'
    'mousedown        .trash': 'toggleTrash'
    'touchstart       .trash': 'toggleTrash'
                
    'touchstart   .labelMask': 'nothing'
    'mouseDown    .labelMask': 'nothing'
    'touchstart            a': 'nothing'
    'mousedown             a': 'nothing'
    'touchstart .clickToEdit': 'nothing'
    'mousedown  .clickToEdit': 'nothing'

    'touchstart   .smallIdea': 'startDrag'
    'mousedown    .smallIdea': 'startDrag'
    'touchmove    .smallIdea': 'continueDrag'
    'mousemove    .smallIdea': 'continueDrag'
    'touchend     .smallIdea': 'stopDrag'
    'touchcancel  .smallIdea': 'stopDrag'
    'mouseup      .smallIdea': 'stopDrag'
                 
    'touchstart  .masonry.group': 'startDragGroup'
    'mousedown   .masonry.group': 'startDragGroup'
    'touchmove   .masonry.group': 'continueDragGroup'
    'mousemove   .masonry.group': 'continueDragGroup'
    'touchend    .masonry.group': 'stopDragGroup'
    'touchcancel .masonry.group': 'stopDragGroup'
    'mouseup     .masonry.group': 'stopDragGroup'


  initialize: (options) ->
    #console.debug 'Dotstorm: NEW DOTSTORM'
    @dotstorm = options.model
    # ID of a single note to show, popped out
    @showId = options.showId
    # name of a tag to show, popped out
    @showTag = options.showTag
    @ideas = options.ideas
    @smallIdeaViews = {}

    @dotstorm.on "change:topic", =>
      #console.debug "Dotstorm: topic changed"
      @renderTopic()
    @dotstorm.on "change:name", =>
      #console.debug "Dotstorm: topic changed"
      @renderTopic()
    @dotstorm.on "change:groups", =>
      #console.debug "Dotstorm: grouping changed"
      # This double-calls... but ok!
      if @dragState? then @abortDrag()
      @renderGroups()
      @renderTrash()
    @ideas.on "add", =>
      #console.debug "Dotstorm: idea added"
      @renderGroups()
    @ideas.on "change:tags", =>
      @renderTagCloud()

    @dotstorm.on "change:sharing", @setAddVisibility
    intertwinkles.user.on "change", @setAddVisibility

  remove: (event) =>
    intertwinkles.user.off "change", @setAddVisibility
    super()

  setAddVisibility: (event) =>
    @$(".add-link-block").toggle(intertwinkles.can_edit(@dotstorm))

  softNav: (event) =>
    event.stopPropagation()
    event.preventDefault()
    ds.app.navigate $(event.currentTarget).attr("href"), trigger: true
    return false

  nothing: (event) =>
    event.stopPropagation()
    event.preventDefault()
    return false

  sortGroups: =>
    # Recursively run through the grouped ideas referenced in the dotstorm sort
    # order, resolving the ids to models, and adding next/prev links to ideas.
    groups = @dotstorm.get("groups")
    prev = null
    linkedGroups = []
    for group in groups
      desc = {
        _id: group._id
        label: group.label
        ideas: []
      }
      for id in group.ideas
        idea = @ideas.get(id)
        idea.prev = prev
        prev.next = idea if prev?
        prev = idea
        desc.ideas.push(idea)
      linkedGroups.push(desc)
    return linkedGroups

  showBig: (model) =>
    # For prev/next navigation, we assume that 'prev' and 'next' have been set
    # on the model for ordering, linked-list style.  This is done by @sortGroups.
    # Without this, prev and next nav buttons just won't show up.
    ds.app.navigate "/dotstorm/d/#{@dotstorm.get("slug")}/#{model.id}/"
    if model.prev?
      model.showPrev = => @showBig(model.prev)
    if model.next?
      model.showNext = => @showBig(model.next)
    big = new ds.ShowIdeaBig model: model
    big.on "close", => @showId = null
    @$el.append big.el
    big.render()

  getTags: () =>
    # Return a hash of tags and counts of tags from all ideas in our
    # collection.
    tags = {}
    hasTags = false
    for idea in @ideas.models
      for tag in idea.get("tags") or []
        hasTags = true
        tags[tag] = (tags[tag] or 0) + 1
    if hasTags
      return tags
    return null

  filterByTag: (tag) =>
    if tag?
      ds.app.navigate "/dotstorm/d/#{@dotstorm.get("slug")}/tag/#{tag}/"
      cleanedTag = $.trim(tag)
      for noteDom in @$(".smallIdea")
        idea = @ideas.get noteDom.getAttribute('data-id')
        if _.contains (idea.get("tags") or []), cleanedTag
          $(noteDom).removeClass("fade")
        else
          $(noteDom).addClass("fade")
      @$("a.tag").removeClass("active").addClass("inactive")
      @$("a.tag[data-tag=\"#{cleanedTag}\"]").addClass("active").removeClass("inactive")
    else
      ds.app.navigate "/dotstorm/d/#{@dotstorm.get("slug")}/"
      @$(".smallIdea").removeClass("fade")
      @$("a.tag").removeClass("inactive active")

  toggleTag: (event) =>
    tag = event.currentTarget.getAttribute("data-tag")
    if tag == @showTag
      @showTag = null
      @filterByTag()
    else
      @showTag = tag
    @filterByTag(@showTag)
    return false

  toggleTrash: (event) =>
    event.preventDefault()
    event.stopPropagation()
    if @dotstorm.get("trash").length > 0
      el = $(".trash")
      el.addClass("dragging")
      el.toggleClass("open")
      el.removeClass("dragging")
    return false
  
  render: =>
    # Re-fetch drop target dims on resize.
    resizeTimeout = null
    $(window).on "resize", => @trigger "resize"
    @on "resize", =>
      clearTimeout(resizeTimeout) if resizeTimeout
      resizeTimeout = setTimeout(
        (=> @ideaAndGroupDims = @getIdeaAndGroupDims()), 100
      )
    $(window).on "mouseup", @stopDrag
    @$el.html @template
      sorting: true
      slug: @model.get("slug")
    @$el.addClass "sorting"
    @renderTagCloud()
    @renderTopic()
    @renderGroups()
    @renderTrash()
    @renderOverlay()

    @setAddVisibility()

    $(".smallIdea").on "touchmove", (event) -> event.preventDefault()
    # iOS needs this.  Argh.
    setTimeout (=> @delegateEvents()), 100
    this

  renderTagCloud: =>
    tags = @getTags()
    max = 0
    min = 100000000000000
    for tag, count of tags
      if count > max
        max = count
      if count < min
        min = count
    minPercent = 90
    maxPercent = 200
    if max == 0
      return
    @$(".tag-links").html("<h2>Tags</h2>")
    for tag, count of tags
      @$(".tag-links").append($("<a/>").attr({
          class: 'tag'
          "data-tag": tag
          href: "/dotstorm/d/#{@model.get("slug")}/tag/#{encodeURIComponent(tag)}"
          style: "font-size: #{minPercent + ((max-(max-(count-min)))*(maxPercent - minPercent) / (max-min))}%"
        }).html( "<nobr>#{_.escapeHTML tag}</nobr>" ), " "
      )

  renderTopic: =>
    @$(".topic").html new ds.Topic(model: @dotstorm).render().el

  renderGroups: =>
    #console.debug "render groups"
    @$("#organizer").html("")
    if @ideas.length == 0
      @$("#organizer").html "To get started, edit the topic or name above, and then add an idea!"
    else
      group_order = @sortGroups()
      _.each group_order, (group, i) =>
        groupView = new ds.ShowIdeaGroup
          position: i
          group: group
          ideaViews: (@getIdeaView(idea) for idea in group.ideas)
        @$("#organizer").append groupView.el
        groupView.render()
        groupView.on "change:label", (group) =>
          @dotstorm.get("groups")[i].label = group.label
          @dotstorm.save null,
            error: (model, err) =>
              console.log("error", err)
              flash "error", "Error saving: #{err}"
          groupView.render()

    @$("#organizer").append("<div style='clear: both;'></div>")
    # Trigger fetching group dims.
    @trigger "resize"

  renderTrash: =>
    @$(".trash .contents").html()
    trash = @dotstorm.get("trash") or []
    _.each trash, (id, i) =>
      idea = @ideas.get(id)
      view = @getIdeaView(idea)
      @$(".trash .contents").append(view.el)
      view.render()
      view.$el.attr("data-idea-position", i)
    if trash.length == 0
      @$(".trash").addClass("empty").removeClass("open")
    else
      @$(".trash").removeClass("empty")

  getIdeaView: (idea) =>
    unless @smallIdeaViews[idea.id]
      view = new ds.ShowIdeaSmall(model: idea)
      @smallIdeaViews[idea.id] = view
    return @smallIdeaViews[idea.id]

  renderOverlay: =>
    if @showId?
      model = @ideas.get(@showId)
      if model? then @showBig model
    else if @showTag?
      @filterByTag(@showTag)
    return this

  getPosition: (event) =>
    pointerObj = event.originalEvent?.touches?[0] or event
    return {
      x: pointerObj.pageX
      y: pointerObj.pageY
    }

  moveNote: =>
    pos = @dragState.lastPos

    # Move the note.
    @dragState.active.css
      position: "absolute"
      left: pos.x + @dragState.mouseOffset.x + "px"
      top: pos.y + @dragState.mouseOffset.y + "px"

    return unless intertwinkles.can_edit(@dotstorm)

    # Clear previous drop target and UI.
    @dragState.currentTarget = null

    # Update current drop target.
    matched = false
    @dragState.placeholder.removeClass("active")
    for type in ["trashIn", "join", "adjacent", "create", "ungroup", "trashOut"]
      for target in @dragState.noteTargets[type]
        if (not @dragState.currentTarget?) and target.match(pos)
          @dragState.currentTarget = target
          target.show()
        else
          target.hide()
    if not @dragState.currentTarget?
      @dragState.placeholder.addClass("active")

    # Handle edge scrolling.
    scrollMargin = 20 # pixels
    scrollTop = $(window).scrollTop()
    if pos.y - scrollTop > @dragState.windowHeight - scrollMargin
      $(window).scrollTop(Math.min(
        Math.max(0, @dragState.documentHeight - @dragState.windowHeight),
        scrollTop + scrollMargin))
    else if pos.y - scrollTop < scrollMargin
      $(window).scrollTop(Math.max(scrollTop - scrollMargin, 0))

    return false

  getElementDims: (el) =>
    return {
      el: el
      offset: el.offset()
      margin:
        left: getPx(el, "margin-left")
        right: getPx(el, "margin-right")
        top: getPx(el, "margin-top")
      outerWidth: el.outerWidth(true)
      outerHeight: el.outerHeight(true)
      width: el.width()
      height: el.height()
    }

  getIdeaAndGroupDims: =>
    dims = {
      ideas: []
      groups: []
      window:
        width: $(window).width()
        height: $(window).height()
      document:
        height: $(document).height()
    }
    for el in @$(".idea-browser .smallIdea")
      el = $(el)
      parent = el.parents("[data-group-position]")
      dim = @getElementDims(el)
      dim.el = el
      dim.inGroup = parent.is(".group")
      dim.ideaPos = parseInt(el.attr("data-idea-position"))
      dim.groupPos = parseInt(parent.attr("data-group-position"))
      dims.ideas.push(dim)
    for el in @$(".idea-browser .masonry.group")
      el = $(el)
      dim = @getElementDims(el)
      dim.el = el
      dim.ideaPos = null
      dim.groupPos = parseInt(el.attr("data-group-position"))
      dims.groups.push(dim)
    return dims

  buildDropTargets: =>
    targets = {
      adjacent: []
      join: []
      create: []
      ungroup: []
      trashOut: []
      trashIn: []
    }
    
    droplineOuterWidth = 44
    droplineExtension = 15
    dims = @ideaAndGroupDims

    # add handlers for combining ideas to create new groups.
    for dim in (dims.ideas or []).concat(dims.groups or [])
      do (dim) =>
        groupActive = false
        unless dim.inGroup or @dragState.groupPos == dim.groupPos
          targets.create.push
            type: "create"
            match: (pos) =>
              return (
                dim.offset.top < pos.y < dim.offset.top + dim.height and \
                dim.offset.left < pos.x < dim.offset.left + dim.width
              )
            show: (pos) =>
              unless groupActive
                dim.el.addClass("hovered")
                groupActive = true
            hide: (pos) =>
              if groupActive
                dim.el.removeClass("hovered")
                groupActive = false
            onDrop: (groupPos, ideaPos) =>
              # Always specify a target ideaPos, even if we are a group and it
              # would thus be null.  This results in a "combine" action rather
              # than "move before".
              @dotstorm.move(
                groupPos, ideaPos,
                dim.groupPos, dim.ideaPos or 0
              )

    # add handlers for consolidated targets for moving.
    moveTargets = {}
    lastGroupPos = 0
    for dim in dims.ideas.concat(dims.groups)
      lastGroupPos = Math.max(lastGroupPos, dim.groupPos)
      ideaPos = if dim.inGroup then dim.ideaPos else null
      left = {
        xlims: if dim.inGroup then [0, 0.5] else [0, 0.3]
        ideaPos: ideaPos
        groupPos: dim.groupPos
        name: 'left'
      }
      right = {
        xlims: if dim.inGroup then [0.5, 1.0] else [0.7, 1.0]
        name: 'right'
      }
      if ideaPos == null
        right.groupPos = dim.groupPos + 1
        right.ideaPos = null
      else
        right.groupPos = dim.groupPos
        right.ideaPos = ideaPos + 1
      for side in [left, right]
        unless moveTargets[side.groupPos]?
          moveTargets[side.groupPos] = {}
        unless moveTargets[side.groupPos][side.ideaPos]?
          moveTargets[side.groupPos][side.ideaPos] = {}
        res = _.extend {
          x1: dim.offset.left + dim.outerWidth * side.xlims[0]
          x2: dim.offset.left + dim.outerWidth * side.xlims[1]
          y1: dim.offset.top
          y2: dim.offset.top + dim.outerHeight
        }, dim
        moveTargets[side.groupPos][side.ideaPos][side.name] = res
    # Extend the drop target on the very last line which extends to the right
    # edge of the window.
    moveTargets[lastGroupPos + 1]?[null]?.right.x2 = @dragState.windowWidth
    # Extend the first to before the beginning.
    moveTargets[0]?[null]?.left.x1 = -50

    for groupPos, ideaPosDims of moveTargets
      for ideaPos, dims of ideaPosDims
        groupPos = parseInt(groupPos)
        if ideaPos != "null"
          ideaPos = parseInt(ideaPos)
        else
          ideaPos = null
        doDims = []
        if dims.left? and dims.right?
          # We actually want "right" to be left of "left", because the terms
          # are referring to which side is the active target. 
          # [note --activeright]center[activeleft -- note]
          if dims.right.x2 > dims.left.x1
            # We've wrapped.
            dims.left.x1 = -50
            dims.right.x2 = @dragState.windowWidth
            doDims.push(dims.left)
            doDims.push(dims.right)
          else
            # Combine the dims -- remember, right is left of left. Think
            # "leftside active".
            dims.left.x1 = dims.right.x1
            dims.left.y1 = Math.min(dims.left.y1, dims.right.y1)
            dims.left.y2 = Math.max(dims.left.y2, dims.right.y2)
            if dims.right.offset.top < dims.left.offset.top
              dims.left.topOffset = dims.right.offset.top - dims.left.offset.top
            dims.left.outerHeight = Math.max(dims.left.outerHeight, dims.right.outerHeight)
            doDims.push(dims.left)
        else
          doDims.push(dims.left or dims.right)
        for dim in doDims
          do (dim, groupPos, ideaPos) =>
            if ideaPos == null
              type = "adjacent"
            else
              type = "join"
            adjacentActive = false
            targets[type].push
              type: type
              match: (pos) =>
                ph = @dragState.placeholderDims
                # This ugly conditional checks whether we should ignore the
                # drop target because it will result in no change in ordering.
                # For example, moving from position 0 to the left side of
                # position 1 is no change; even though the position has a
                # different number.  Remember that the arguments to
                # @dotstorm.move assume "put me to the left of the named
                # destination" unless you specify an offset to the right.
                #
                # Also, ignore any drop targets that overlap with the place
                # holder from where the note was picked up.  This avoids the
                # case of clicking on an idea and accidentally ungrouping it,
                # since the group's "put outside of me" drop target overlaps
                # with the placeholder.
                if (ph.x1 <= pos.x <= ph.x2 and ph.y1 <= pos.y <= ph.y2) or \
                   (@dragState.inGroup == false and ideaPos == null and \
                     (groupPos == @dragState.groupPos or \
                      groupPos - 1 == @dragState.groupPos)) or \
                   (@dragState.isGroup == true and \
                     groupPos == @dragState.groupPos) or \
                   (groupPos == @dragState.groupPos and \
                     (ideaPos == @dragState.ideaPos or \
                       ideaPos - 1 == @dragState.ideaPos))
                  return false
                return dim.x1 < pos.x < dim.x2 and dim.y1 < pos.y < dim.y2
              show: =>
                unless adjacentActive
                  adjacentActive = true
                  dim.el.append(@dragState.dropline)
                  # Right side hack... to tell whether to draw the dropline on
                  # the right or the left, see if the target position is
                  # greater than our current position.
                  if (ideaPos == null and groupPos > dim.groupPos) or \
                      (ideaPos != null and ideaPos > dim.ideaPos)
                    leftOffset = dim.outerWidth
                  else
                    leftOffset = 0
                  @dragState.dropline.show().css
                    top: -droplineExtension + (dim.topOffset or 0)
                    left: -droplineOuterWidth / 2 - dim.margin.left + leftOffset - 1
                    height: dim.outerHeight + droplineExtension * 2
              hide: =>
                if adjacentActive
                  adjacentActive = false
                  if not _.contains ["adjacent", "join"], @dragState.currentTarget?.type
                    @dragState.dropline.hide()
              onDrop: (sourceGroupPos, sourceIdeaPos) =>
                @dotstorm.move(
                  sourceGroupPos, sourceIdeaPos, groupPos, ideaPos
                )

    # Trash
    trash = @$(".trash")
    # Drag into trash
    trashActive = false
    targets.trashIn.push {
      type: "trashIn"
      match: (pos) =>
        tp = @dragState.trashDims
        return tp.offset.left < pos.x < tp.offset.left + tp.outerWidth and \
          tp.offset.top < pos.y < tp.offset.top + tp.outerHeight
      show: =>
        unless trashActive
          trashActive = true
          unless @dragState.groupPos == null
            trash.addClass("active")
        if @dragState.groupPos == null
          @dragState.placeholder.addClass("active")
      hide: =>
        if trashActive
          trashActive = false
          trash.removeClass("active")
      onDrop: (groupPos, ideaPos) =>
        unless groupPos == null
          @dotstorm.move(groupPos, ideaPos, null, null)
    }
    # Drag out of trash (but not into another explicit target)
    targets.trashOut.push {
      type: "trashOut"
      match: (pos) =>
        tp = @dragState.trashDims
        return (
          @dragState.groupPos == null and tp? and not (
            tp.offset.left < pos.x < tp.offset.left + tp.outerWidth and \
            tp.offset.top < pos.y < tp.offset.top + tp.outerHeight)
        )
      show: ->
      hide: ->
      onDrop: (groupPos, ideaPos, idea_id) =>
        end = 0 #@dotstorm.get("groups").length + 1
        @dotstorm.move(groupPos, ideaPos, end, null)
        $(".smallIdea[data-id=#{idea_id}]").css({
          "outline-width": "12px"
          "outline-style": "solid"
          "outline-color": "rgba(255, 200, 0, 1.0)"
        }).animate({
          "outline-width": "12px"
          "outline-style": "solid"
          "outline-color": "rgb(255, 255, 255, 0.0)"
        }, 5000, ->
          $(this).css
            "outline-width": ""
            "outline-style": ""
            "outline-color": ""
        )
    }
    return targets


  startDragGroup: (event) =>
    console.log "startDragGroup"
    return @startDrag(event)
  startDrag: (event) =>
    event.preventDefault()
    event.stopPropagation()
    if event.type == "touchstart"
      @isTouch = true
    else if @isTouch
      return
    active = $(event.currentTarget)
    activeOffset = active.offset()
    activeWidth = active.outerWidth(true)
    activeHeight = active.outerHeight(true)
    @dragState = {
      startTime: new Date().getTime()
      active: active
      offset: active.position()
      targetDims: []
      dropline: $("<div class='dropline'></div>")
      placeholder: $("<div class='placeholder'></div>").css
        float: "left"
        width: (activeWidth) + "px"
        height: (activeHeight) + "px"
      placeholderDims:
        x1: activeOffset.left
        y1: activeOffset.top
        x2: activeOffset.left + activeWidth
        y2: activeOffset.top + activeHeight
      startPos: @getPosition(event)
      windowHeight: $(window).height()
      windowWidth: $(window).width()
      documentHeight: $(document).height()
    }
    @dragState.lastPos = @dragState.startPos
    @dragState.mouseOffset =
      x: @dragState.offset.left - @dragState.startPos.x
      y: @dragState.offset.top - @dragState.startPos.y

    trash = @$(".trash")
    if intertwinkles.can_edit(@dotstorm)
      trash.addClass("dragging")
    # Re-calculate on drag start, because it might be "open" or "closed" since
    # last re-render.
    @dragState.trashDims = {
      offset: trash.offset()
      outerWidth: trash.outerWidth(true)
      outerHeight: trash.outerHeight(true)
    }
    if @dragState.active.is(".group")
      @dragState.activeParent = @dragState.active
      @dragState.isGroup = true
      @dragState.inGroup = false
    else
      @dragState.activeParent = @dragState.active.parents("[data-group-position]")
      @dragState.isGroup = false
      @dragState.inGroup = @dragState.activeParent.is(".group")
    @dragState.groupPos = parseInt(@dragState.activeParent.attr("data-group-position"))
    if isNaN(@dragState.groupPos)
      @dragState.groupPos = null
    @dragState.ideaPos = parseInt(@dragState.active.attr("data-idea-position"))
    if isNaN(@dragState.ideaPos)
      @dragState.ideaPos = null

    @dragState.noteTargets = @buildDropTargets()

    active.addClass("active")
    @dragState.active.before(@dragState.placeholder)

    @moveNote()

    # Add window as a listener, so if we drag too fast and aren't on top of it
    # any more, we still pull the note along. Remove this again at @stopDrag.
    $(window).on "mousemove", @continueDrag
    $(window).on "touchmove", @continueDrag
    return false

  continueDragGroup: (event) => return @continueDrag(event)
  continueDrag: (event) =>
    if @isTouch and event.type != "touchmove"
      return
    if @dragState?
      @dragState.lastPos = @getPosition(event)
      @moveNote()
    return false

  getGroupPosition: ($el) ->
    # Get the group position of the draggable entity (either a group or an
    # idea).  Returns [groupPos, ideaPos or null]
    if $el.hasClass("group")
      return [parseInt($el.attr("data-group-position")), null]
    return [
      parseInt($el.parents("[data-group-position]").attr("data-group-position"))
      parseInt($el.attr("data-idea-position"))
    ]

  abortDrag: =>
    $(window).off "mousemove", @continueDrag
    $(window).off "touchmove", @continueDrag
    @$(".hovered").removeClass("hovered")
    @$(".trash").removeClass("dragging active")
    if @dragState?
      @dragState.active?.removeClass("active")
      @dragState.active?.css
        position: "relative"
        left: 0
        top: 0
      @dragState.placeholder?.remove()
      @dragState.dropline?.remove()
    @dragState = null

  stopDragGroup: (event) => @stopDrag(event)
  stopDrag: (event) =>
    event?.preventDefault()
    if @isTouch and event?.type == "mouseend"
      return
    state = @dragState
    @abortDrag()
    unless state?
      return false

    if (not state.active.is(".group")) and @checkForClick(state)
      @showBig(@ideas.get(state.active.attr("data-id")))
      return false

    if state.currentTarget?
      state.currentTarget.onDrop(state.groupPos, state.ideaPos,
                                 state.active.attr("data-id"))
      @dotstorm.trigger("change:groups")
      @dotstorm.save null, {
        error: (model, err) =>
          console.log("error", model, err)
          flash "error", "Error saving: #{err}"
      }
    return false

  checkForClick: (state) =>
    # A heuristic for distinguishing clicks from drags, based on time and
    # distance.
    distance = Math.sqrt(
        Math.pow(state.lastPos.x - state.startPos.x, 2) +
        Math.pow(state.lastPos.y - state.startPos.y, 2)
    )
    elapsed = new Date().getTime() - state.startTime
    return distance < 20 and elapsed < 400
