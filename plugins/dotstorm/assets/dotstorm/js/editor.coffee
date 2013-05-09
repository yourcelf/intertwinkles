
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
    @idea.save(attrs, {
      success: (model) =>
        @$("input[type=submit]").removeClass("loading")
        if ideaIsNew
          @dotstorm.addIdea(model, silent: true)
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
