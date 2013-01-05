#= require ../intertwinkles/js/intertwinkles/index

intertwinkles.build_toolbar($("header"), {applabel: "twinklepad"})
intertwinkles.build_footer($("footer"))

class TwinklePad extends Backbone.Model

tp = {}
if INITIAL_DATA.twinklepad?
  tp.model = new TwinklePad(INITIAL_DATA.twinklepad)
  tp.sharing_button = new intertwinkles.SharingSettingsButton(model: tp.model)
  $("li.sharing").html(tp.sharing_button.el)
  tp.sharing_button.render()

socket = io.connect("/iorooms")

socket.on "error", (data) ->
  flash "error", "Oh noes, server error."
  window.console?.log?(data.error)

socket.on "connect", ->
  intertwinkles.socket = socket
  if tp.model?
    socket.emit "join", {room: tp.model.get("pad_id")}

    tp.sharing_button.on "save", (sharing_settings) ->
      socket.once "twinklepad", ->
        tp.sharing_button.close()

      socket.emit "save_twinklepad", {
        twinklepad: _.extend tp.model.toJSON(), {sharing:  sharing_settings}
      }

socket.on "twinklepad", (data) ->
  if intertwinkles.can_edit(data.twinklepad) != intertwinkles.can_edit(tp.model)
    window.location.href = window.location.href
  else if not intertwinkles.can_view(data.twinklepad)
    flash "error", "Permission to view has been revoked."
    window.location.href = "/"
  else
    tp.model.set(data.twinklepad)

socket.on "error", (data) ->
  flash "error", "Oh noes, server error."
  tp.sharing_button?.close()
  window.console?.log?(data.error)

# Scale iframe up.
resize = ->
  window_height = $(window).height()
  height = Math.min(
    window_height,
    Math.max(400, window_height - $("iframe").position().top - $("footer").height() - 10)
  )
  $("#etherpad").css("height", "#{height}px")
resize()
$(window).on "resize", resize
