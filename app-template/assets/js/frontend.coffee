#= require ../intertwinkles/js/intertwinkles/index

intertwinkles.build_toolbar($("header"), {appname: "home"})
intertwinkles.build_footer($("footer"))

socket = io.connect("/iorooms")
socket.on "error", (data) ->
  flash "error", "Oh noes, server error."
  window.console?.log?(data.error)

socket.on "connect", ->
  intertwinkles.socket = socket
