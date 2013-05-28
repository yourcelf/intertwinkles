ds.fillSquare = (el, container, max=600, min=240) ->
  totalHeight = $(window).height()
  totalWidth = $(window).width()
  top = container.position().top
  el.css("height", 0)
  containerHeight = container.outerHeight(true)
  elHeight = Math.min(max, Math.max(min, totalHeight - top - containerHeight))
  elWidth = Math.max(Math.min(totalWidth, elHeight), min)
  elWidth = elHeight = Math.min(elWidth, elHeight)
  el.css
    height: elHeight + "px"
    width: elWidth + "px"
  return [elWidth, elHeight]

class ds.Intro extends intertwinkles.BaseView
  template: _.template $("#intro").html()
  events:
    'click .softnav': 'softNav'
  render: =>
    @$el.html(@template())
    this

class ds.EditDotstorm extends intertwinkles.BaseView
  chars: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890"
  template: _.template $("#createTemplate").html()
  events:
    'click .show-add-form': 'showForm'
    'submit form':          'submit'
    'keyup [name=name]':    'changeName'
    'keyup [name=slug]':    'changeSlug'

  initialize: (options={}) ->
    super()
    @_slugIsCustom = false
    randomChar = =>
      @chars.substr parseInt(Math.random() * @chars.length), 1
    @randomSlug = (randomChar() for i in [0...12]).join("")
    @model = options.model or new ds.Dotstorm()

  validate: =>
    return @validateFields "form", [
      ["#id_slug", ((val) =>
        unless @slugUnavailable
          return $.trim(val) or @randomSlug
        return null
      ), "This name is not available."],
      ["#id_name", ((val) => $.trim(val) or ""), ""],
      ["#id_sharing", ((val) => @sharingControl.sharing), "", "sharing"],
    ]

  render: =>
    @$el.html @template(model: @model.toJSON(), randomSlug: @randomSlug)
    @sharingControl?.remove()
    @sharingControl = new intertwinkles.SharingFormControl()
    @addView("#sharingControl", @sharingControl)
    this

  showForm: (event) =>
    event.preventDefault()
    @$(".show-add-form").hide()
    @$("form").show()

  submit: (event) =>
    event.preventDefault()
    cleaned_data = @validate()
    if cleaned_data
      #FIXME
      @model.save({
        name: cleaned_data.name
        slug: cleaned_data.slug
        sharing: cleaned_data.sharing
      }, (err, model) -> @trigger("save", model))

  changeName: (event) =>
    unless @_slugIsCustom
      slug = intertwinkles.slugify(@$("[name=name]").val())
      @$("[name=slug]").val(slug)
      @checkSlug(slug)

  changeSlug: (event) =>
    val = @$("[name=slug]").val()
    @_slugIsCustom = val != ""
    @checkSlug(val)

  checkSlug: (val) =>
    val or= @randomSlug
    @$(".slug-val").html("#{encodeURIComponent(val)}")
    if val and val != @model.get("slug")
      parent = @$("[name=slug]").closest(".control-group")
      intertwinkles.socket.send "dotstorm/check_slug", {slug: val}
      intertwinkles.socket.once "dotstorm:check_slug", (data) =>
        parent.removeClass('error')
        parent.find(".error-msg").remove()
        if not data.available
          @slugUnavailable = true
          @$(".dotstorm-url").hide()
          parent.addClass('error')
          @$("#id_slug").after(
            "<span class='help-inline error-msg'>Name not available</span>"
          )
        else
          @slugUnavailable = false
          @$(".dotstorm-url").show()

class ds.Topic extends Backbone.View
  #
  # An editor and viewer for a dotstorm "topic" -- just some text that
  # describes an idea.
  #
  template: _.template $("#dotstormTopic").html() or ""
  textareaEditorTemplate: _.template $("#dotstormInPlaceTextarea").html() or ""
  inputEditorTemplate: _.template $("#dotstormInPlaceInput").html() or ""

  events:
    'click    .topicEdit .clickToEdit': 'editTopic'
    'touchend .topicEdit .clickToEdit': 'editTopic'
    'submit           .topicEdit form': 'saveTopic'
    'click     .nameEdit .clickToEdit': 'editName'
    'touchend  .nameEdit .clickToEdit': 'editName'
    'submit            .nameEdit form': 'saveName'
    'click                    .cancel': 'cancel'
    'touchend                 .cancel': 'cancel'

  initialize: (options) ->
    @model = options.model
    @listenTo @model, "change", @render
    @listenTo intertwinkles.user, "change", @render

  render: =>
    #console.debug "render topic"
    @$el.html @template
      name: @model.get("name")
      topic: @model.get("topic") or "Click to edit topic..."
      embed_slug: @model.get("embed_slug")
      url: window.location.href
    unless intertwinkles.can_edit(@model)
      @$(".clickToEdit").removeClass("clickToEdit")
    this

  editName: (event) =>
    $(event.currentTarget).replaceWith @inputEditorTemplate text: @model.get("name")
    @$("input[text]").select()
    return false

  saveName: (event) =>
    event.stopPropagation()
    event.preventDefault()
    val = @$(".nameEdit input[type=text]").val()
    if val == @model.get("name")
      @render()
    else
      #FIXME
      @model.save({name: val})
    return false

  editTopic: (event) =>
    $(event.currentTarget).hide().after @textareaEditorTemplate text: @model.get("topic")
    @$("textarea").select()
    return false

  saveTopic: (event) =>
    val = @$(".topicEdit textarea").val()
    if val == @model.get("topic")
      @render()
    else
      #FIXME
      @model.save({topic: val})
    return false

  cancel: (event) =>
    @render()
    return false


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

    @listenTo @dotstorm, "change:topic", =>
      #console.debug "Dotstorm: topic changed"
      @renderTopic()
    @listenTo @dotstorm, "change:name", =>
      #console.debug "Dotstorm: topic changed"
      @renderTopic()
    @listenTo @dotstorm, "change:groups", =>
      #console.debug "Dotstorm: grouping changed"
      # This double-calls... but ok!
      if @dragState? then @abortDrag()
      @renderGroups()
      @renderTrash()
    @listenTo @ideas, "add", =>
      #console.debug "Dotstorm: idea added"
      @renderGroups()
    @listenTo @ideas, "change:tags", =>
      @renderTagCloud()

    @listenTo @dotstorm, "change:sharing",  @setAddVisibility
    @listenTo intertwinkles.user, "change", @setAddVisibility

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
        }).html( "<nobr>#{_.escape tag}</nobr>" ), " "
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
          #FIXME
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
      startTime: intertwinkles.now().getTime()
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
      #FIXME
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
    elapsed = intertwinkles.now().getTime() - state.startTime
    return distance < 20 and elapsed < 400

class ds.ShowIdeaGroup extends Backbone.View
  template: _.template $("#dotstormSmallIdeaGroup").html() or ""
  editTemplate: _.template $("#dotstormSmallIdeaGroupEditLabel").html() or ""
  events:
    'click    .grouplabel': 'editLabel'
    'touchend .grouplabel': 'editLabel'
    'click        .cancel': 'cancelEdit'
    'touchend     .cancel': 'cancelEdit'
    'submit          form': 'saveLabel'

  initialize: (options) ->
    @group = options.group
    @ideaViews = options.ideaViews
    @position = options.position

  editLabel: (event) =>
    unless @editing
      event.stopPropagation()
      event.preventDefault()
      @editing = true
      $(event.currentTarget).html @editTemplate
        label: @group.label or ""
      @$("input[type=text]").select()

  cancelEdit: (event) =>
    event.stopPropagation()
    event.preventDefault()
    @editing = false
    @render()
    return false
  
  saveLabel: (event) =>
    event.stopPropagation()
    event.preventDefault()
    @editing = false
    @group.label = @$("input[type=text]").val()
    @trigger "change:label", @group
    return false

  render: =>
    @$el.html @template
      showGroup: @ideaViews.length > 1
      label: @group.label
      group_id: @group._id
    @$el.addClass("masonry")
    if @ideaViews.length > 1
      @$el.addClass("group")
    @$el.attr({
      "data-group-id": @group._id
      "data-group-position": @position
    })
    container = @$(".ideas")
    container.css("height", "100%")
    _.each @ideaViews, (view, i) =>
      container.append view.el
      view.$el.attr("data-idea-position", i)
      view.render()
    this

class ds.ShowIdeaSmall extends Backbone.View
  template: _.template $("#dotstormSmallIdea").html() or ""
  initialize: (options) ->
    @model = options.model
    @size = options.size or "medium"
    @listenTo @model, "change:tags", @render
    @listenTo @model, "change:imageVersion", @render
    @listenTo @model, "change:description", @render
    @listenTo @model, "change:photo", @render

  render: =>
    args = _.extend
      tags: []
      description: ""
    , @model.toJSON()
    @$el.html @template args
    @$el.attr("data-id", @model.id)
    @$el.addClass("smallIdea")
    @renderVotes()

  renderVotes: =>
    @$(".votes").html new ds.VoteWidget({
      idea: @model
      readOnly: true
      hideOnZero: true
    }).render().el

class ds.ShowIdeaBig extends Backbone.View
  template: _.template $("#dotstormBigIdea").html() or ""
  editorTemplate: _.template $("#dotstormInPlaceInput").html() or ""
  events:
    'mousedown .shadow': 'close'
    'touchstart .shadow': 'close'

    'mousedown .close': 'close'
    'touchstart .close': 'close'

    'mousedown .next': 'next'
    'touchstart .next': 'next'

    'mousedown .prev': 'prev'
    'touchstart .prev': 'prev'

    'mousedown .edit': 'edit'
    'touchstart .edit': 'edit'

    'click .tags .clickToEdit': 'editTags'
    'submit .tags form': 'saveTags'

    'mousedown .note': 'nothing'
    'touchstart .note': 'nothing'

  initialize: (options) ->
    @model = options.model
    @listenTo @model, "change:description", @render
    @listenTo @model, "change:tags", @render
    @listenTo @model, "change:background", @render
    @listenTo @model, "change:drawing", @render
    @listenTo @model, "change:photo", @render
    @listenTo @model, "change:sharing", @render
    @listenTo intertwinkles.user, "change", @render

  render: =>
    #console.debug "render big", @model.get "imageVersion"
    args = _.extend {
      tags: []
      description: ""
      hasNext: @model.showNext?
      hasPrev: @model.showPrev?
    }, @model.toJSON()
    @$el.html @template args
    @$el.addClass("bigIdea")
    resize = =>
      noteHeight = @$(".note").outerHeight(true) - @$(".canvasHolder").outerHeight(true)
      maxImgHeight = $(window).height() - noteHeight
      @$(".canvasHolder").css("max-height", $(window).height() - noteHeight)
      @$(".note").css("width", Math.min(640, maxImgHeight))
      # hack for mobile which doesn't support 'fixed'
      @$(".note")[0].scrollIntoView()
    @$(".note img").on "load", resize
    resize()
    @renderVotes()
    $(window).on "resize", resize
    unless intertwinkles.can_edit(ds.model)
      @$(".clickToEdit").removeClass("clickToEdit")
      @$(".toolbar .edit").hide()
    this

  renderVotes: =>
    @$(".vote-widget").html new ds.VoteWidget(idea: @model).render().el

  close: (event) =>
    if event?
      event.preventDefault()
      event.stopPropagation()
    @trigger "close", this
    @$el.remove()
    ds.app.navigate "/dotstorm/d/#{ds.model.get("slug")}/"
    return false

  nothing: (event) =>
    event.stopPropagation()
    #event.preventDefault()

  next: (event) =>
    event.stopPropagation()
    @close()
    @model.showNext() if @model.showNext?
    return false

  prev: (event) =>
    event.stopPropagation()
    @close()
    @model.showPrev() if @model.showPrev?
    return false

  edit: (event) =>
    event.stopPropagation()
    event.preventDefault()
    ds.app.navigate "/dotstorm/d/#{ds.model.get("slug")}/edit/#{@model.id}/",
      trigger: true
    return false

  editTags: (event) =>
    event.stopPropagation()
    @$(event.currentTarget).replaceWith @editorTemplate
      text: (@model.get("tags") or []).join(", ")
    @$("input[type=text]").select()
    return false

  saveTags: (event) =>
    val = @$(".tags input[type=text]").val()
    #FIXME
    @model.save({tags: @model.cleanTags(val)})
    return false

class ds.IdeaCanvas extends Backbone.View
  #
  # A canvas element suitable for drawing and recalling drawn ideas.
  #
  tagName: "canvas"
  events:
    'mousedown':  'handleStart'
    'touchstart': 'handleStart'
    'mouseup':    'handleEnd'
    'touchend':   'handleEnd'
    'mousemove':  'handleDrag'
    'touchmove':  'handleDrag'

  initialize: (options) ->
    @idea = options.idea
    # don't listen for changes to @idea.. cuz we're busy drawing!
    @tool = "pencil"
    $(window).on 'mouseup', @handleEnd
    @canvas = @$el

  render: =>
    @ctxDims = @idea.get("dims") or { x: 600, y: 600 }
    @canvas.attr { width: @ctxDims.x, height: @ctxDims.y }

    @ctx = @canvas[0].getContext('2d')
    @actions = @idea.get("drawing")?.slice() or []
    if @idea.get("background")?
      @background = @idea.get("background")
    else
      @$("a.note-color:first").click()
    @redraw()
    # iOS needs this.  Argh.
    setTimeout (=> @delegateEvents()), 100
  
  redraw: =>
    @lastTool = null
    for action in @actions
      @drawAction(action)

  getPointer: (event) =>
    if event.originalEvent.touches?
      touch = event.originalEvent.touches?[0] or event.originalEvent.changedTouches?[0]
      pointerObj = touch
      @isTouch = true
    else
      pointerObj = event
    @pointer =
      x: parseInt((pointerObj.pageX - @offset.left) / @curDims.x * @ctxDims.x)
      y: parseInt((pointerObj.pageY - @offset.top) / @curDims.y * @ctxDims.y)
    return @pointer

  handleStart: (event) =>
    if @disabled then return
    event.preventDefault()
    event.stopPropagation()
    if event.type == "touchstart"
      @_isTouch = true
    @offset = @canvas.offset()
    @curDims = { x: @canvas.width(), y: @canvas.height() }
    @mouseIsDown = true
    @getPointer(event)
    @handleDrag(event)
    return false

  handleDrag: (event) =>
    event.preventDefault()
    event.stopPropagation()
    if @disabled or (@_isTouch and event.type == "mousemove")
      # Android 4.0 browser throws a mousemove in here after 100 milliseconds
      # or so.  Assume that if we've seen one touch event, we're touch only.
      return false
    if @mouseIsDown
      old = @pointer
      @getPointer(event)
      if old?.x and old.x == @pointer.x and old.y == @pointer.y
        old.x -= 1
      action = [@tool, old?.x, old?.y, @pointer.x, @pointer.y]
      @drawAction(action)
      @actions.push(action)
    return false

  handleEnd: (event) =>
    event.preventDefault()
    @mouseIsDown = false
    @pointer = null
    return false

  drawAction: (action) =>
    tool = action[0]
    if tool != @lastTool
      switch tool
        when 'pencil'
          @ctx.lineCap = 'round'
          @ctx.lineWidth = 8
          @ctx.strokeStyle = '#000000'
        when 'eraser'
          @ctx.lineCap = 'round'
          @ctx.lineWidth = 32
          @ctx.strokeStyle = @background
      @lastTool = tool

    @ctx.beginPath()
    if action[1]?
      @ctx.moveTo action[1], action[2]
    else
      @ctx.moveTo action[3], action[4]
    @ctx.lineTo action[3], action[4]
    @ctx.stroke()

class ds.CameraGrabber extends intertwinkles.BaseModalFormView
  template: _.template $("#dotstormCameraDialog").html()
  events:
    'submit form':           'submit'
    'click .toggle-capture': 'toggleCapture'
    'click .cheese':         'snapshot'
  initialize: (options) ->
    # De-prefix getters.
    navigator.getUserMedia = (navigator.getUserMedia or navigator.webkitGetUserMedia or
      navigator.mozGetUserMedia or navigator.msGetUserMedia)
    window.URL = window.URL or window.webkitURL or window.mozURL or window.msURL
    @$el.on 'hidden', => @stream?.stop()

  toggleCapture: (event) =>
    event.preventDefault()
    if @stream?
      @handleNoStream()
    else
      $(event.currentTarget).addClass("loading")
      navigator.getUserMedia({video: true}, @handleStream, @handleNoStream)

  handleStream: (stream) =>
    @stream = stream
    @$(".capture").show()
    $(window).resize() # trigger re-positioning of modal
    @$(".toggle-capture").attr("value", "Stop camera").removeClass("loading")
    video = document.querySelector('#monitor')
    if video.mozSrcObject != undefined
      video.mozSrcObject = stream
      video.src = stream
    else
      video.src = window.URL?.createObjectURL?(stream) or stream
    video.play()

  handleNoStream: (err) =>
    if err?
      flash "info", "Can't access camera."
    if @stream?
      video = document.querySelector("#monitor")
      video.pause()
      @stream.stop()
      @stream = null
    @$(".toggle-capture").attr("value", "Use camera").removeClass("loading")
    @$(".capture").hide()
    $(window).resize() # trigger re-positioning of modal

  snapshot: (event) ->
    event.preventDefault()
    if @stream
      video = document.querySelector('#monitor')
      canvas = document.querySelector('#photo')
      ctx = canvas.getContext('2d')
      ctx.drawImage(video, 0, 0)
      @imageDataURL = canvas.toDataURL('image/png')

  submit: (event) =>
    event.preventDefault()
    @$("input[type=submit]").addClass("loading")
    if @$("input[type=file]").val()
      @trigger "file", @$("input[type=file]")[0].files[0]
    else if @imageDataURL
      console.log "triggering a data url"
      @trigger "dataURL", @imageDataURL
    else
      @remove()

class ds.EditIdea extends Backbone.View
  #
  # Container for editing ideas, including a canvas for drawing, a form for
  # adding descriptions and tags, and access to the camera if available.
  #
  template: _.template $("#dotstormAddIdea").html() or ""
  events:
    'submit             form': 'saveIdea'
    'click             .tool': 'changeTool'
    'touchend          .tool': 'changeTool'
    'click       .note-color': 'handleChangeBackgroundColor'
    'touchend    .note-color': 'handleChangeBackgroundColor'
    'change input.file-input': 'fileAdded'

  initialize: (options) ->
    @idea = options.idea
    @dotstorm = options.dotstorm
    @canvas = new ds.IdeaCanvas {idea: @idea}
    @cameraEnabled = not not (navigator.getUserMedia or navigator.webkitGetUserMedia or
      navigator.mozGetUserMedia or navigator.msGetUserMedia)

  render: =>
    fileEnabled = window.File and window.FileReader and window.FileList and window.Blob

    @$el.html @template
      longDescription: @idea.get "longDescription"
      description: @idea.get "description"
      tags: @idea.get("tags") or ""
      cameraEnabled: @cameraEnabled
      fileEnabled: fileEnabled

    # Using this hack for file input styling:
    # http://stackoverflow.com/a/3226279
    if fileEnabled
      @$("input.file-input").wrap(
        $("<div/>").css { height: 0, width: 0, overflow: "hidden" }
      )

    @changeBackgroundColor @idea.get("background") or @$(".note-color:first").css("background-color")
    @noteTextarea = @$("#id_description")
    @$(".canvas").append(@canvas.el)
    if @idea.get("photoURLs")?.full
      photo = $("<img/>").attr(
        src: @idea.get("photoURLs").full
        alt: "Loading..."
      ).css("width", "100%")
      photo.on "load", -> photo.attr "alt", "photo thumbnail"
      @$(".photo").html photo

    @canvas.render()
    @tool = 'pencil'
    #
    # Canvas size voodoo
    #
    $(window).on "resize", @resize
    setTimeout(@resize, 1) # Timeout avoids crash in iOS safari 4.3.3
    this

  resize: =>
    [width, height] = ds.fillSquare(@$(".canvasHolder"), @$el, 600, 320)
    @$("#addIdea").css "width", width + "px"
    @$(".canvasHolder textarea").css "fontSize", (height / 10) + "px"

  changeFile: =>
    @$("input.file-input").click()

  fileAdded: (event) =>
    handleFile(event.originalEvent.target.files[0])

  handleFile: (file) =>
    if file? and file.type.match('image.*')
      @$(".file-upload").addClass("loading")
      reader = new FileReader()
      reader.onload = (e) =>
        # Make 640x480 max thumbnail.
        img = new Image()
        img.src = e.target.result
        img.onload = =>
          canvas = document.createElement("canvas")
          canvas.width = 640
          canvas.height = 480
          aspect = img.height / img.width
          scale = Math.min(1, canvas.width / img.width, canvas.height / img.height)
          w = img.width * scale
          h = w * aspect
          x = (canvas.width - w)/2
          ctx = canvas.getContext('2d')
          ctx.drawImage(img, x, 0, w, h)
          data = canvas.toDataURL()
          parts = data.split(",")
          @setPhoto(parts[1], parts[0] + ",")
          @$(".file-upload").removeClass("loading")
      reader.readAsDataURL(file)
    else
      flash "info", "File not recognized as an image.  Try another."
      @$(".file-input").val("")

  setPhoto: (imageData, prefix="data:image/jpg;base64,") =>
    @photo = imageData
    @$(".photo").html $("<img/>").attr(
      "src", prefix + imageData
    ).css({width: "100%"})

  saveIdea: (event) =>
    @$("input[type=submit]").addClass("loading")
    ideaIsNew = not @idea.id?
    attrs = {
      dotstorm_id: @dotstorm.id
      description: $("#id_description").val()
      tags: @idea.cleanTags($("#id_tags").val())
      background: @canvas.background
      dims: @canvas.ctxDims
      drawing: @canvas.actions
      editor: intertwinkles.user?.id
      photoData: @photo
    }
    #FIXME
    @idea.save(attrs, {
      success: (model) =>
        @$("input[type=submit]").removeClass("loading")
        if ideaIsNew
          @dotstorm.addIdea(model, silent: true)
          #FIXME
          @dotstorm.save null, {
            error: (model, err) =>
              console.error "error", err
              flash "error", "Error saving: #{err}"
          }
          ds.ideas.add(model)
        ds.app.navigate "/dotstorm/d/#{@dotstorm.get("slug")}/", trigger: true
        $(".smallIdea[data-id=#{@idea.id}]").css({
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

      error: (model, err) ->
        @$("input[type=submit]").removeClass("loading")
        console.log("error", err)
        str = err.error?.message
        flash "error", "Error saving: #{str}. See log for details."
    })
    return false

  changeTool: (event) =>
    event.preventDefault()
    event.stopPropagation()
    if event.type == "touchend"
      @_isTouch = true
    else if @_isTouch
      return false
    el = $(event.currentTarget)
    tool = el.attr("data-tool")
    @$(".tool").removeClass("active")
    switch tool
      when "camera"
        @promptForPhoto()
        el = @$(".tool[data-tool=text]")
        el.addClass("active")
      when "file-upload"
        @changeFile()
      when "text"
        @$(".text").before(@$(".canvas"))
        el.addClass("active")
      when "eraser", "pencil"
        @$(".text").after(@$(".canvas"))
        @canvas.tool = tool
        el.addClass("active")
    return false

  promptForPhoto: (event) =>
    grabber = new ds.CameraGrabber()
    grabber.on "file", (file) =>
      @handleFile(file)
      grabber.remove()
    grabber.on "dataURL", (dataURL) =>
      parts = dataURL.split(",")
      @setPhoto(parts[1], parts[0] + ",")
      grabber.remove()
    grabber.render()

  handleChangeBackgroundColor: (event) =>
    @changeBackgroundColor $(event.currentTarget).css("background-color")
    @canvas.redraw()
    return false

  changeBackgroundColor: (color) =>
    @canvas.background = color
    @$(".canvasHolder").css "background", @canvas.background

class ds.VoteWidget extends Backbone.View
  template: _.template $("#dotstormVoteWidget").html() or ""
  events:
    'touchstart   .upvote': 'upVote'
    'mousedown    .upvote': 'upVote'
    'touchstart .downvote': 'downVote'
    'mousedown  .downvote': 'downVote'
  initialize: (options) ->
    @idea = options.idea
    @listenTo @idea, "change:votes", @update
    @readOnly = options.readOnly
    @hideOnZero = options.hideOnZero
    if @readOnly
      @undelegateEvents()
    @listenTo intertwinkles.user, "change", @render
    @listenTo ds.model, "change:sharing", @render

  render: =>
    #console.debug "render votewidget", @idea.id
    @$el.addClass("vote-widget")
    @$el.html @template(readOnly: @readOnly)
    @update()
    unless intertwinkles.can_edit(ds.model)
      @$(".upvote, .downvote").hide()
    this

  update: =>
    votes = @idea.get("votes") or 0
    @$(".vote-count").html votes
    if @hideOnZero
      if votes == 0
        @$el.hide()
      else
        @$el.show()

  upVote: (event) =>
    return @changeVote(event, 1, ".upvote")
  downVote: (event) =>
    return @changeVote(event, -1, ".downvote")

  changeVote: (event, direction, controlSelector) =>
    event.stopPropagation()
    event.preventDefault()
    # Must copy array; otherwise change events don't fire properly.
    if @timeoutFor == controlSelector
      return false
    #FIXME
    @idea.save {votes: Math.max(0, (@idea.get("votes") or 0) + direction)}
    selectorList = [".vote-count"]
    if controlSelector? then selectorList.push(controlSelector)
    selectors = selectorList.join(", ")
    @$(selectors).addClass("active")
    @timeoutFor = controlSelector
    setTimeout =>
      @$(selectors).removeClass("active")
      @timeoutFor = null
    , 2000
    return false

