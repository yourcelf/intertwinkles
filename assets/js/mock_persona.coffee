navigator.id = {
  watch: (handlers) ->
    @handlers = handlers
  request: ->
  logout: ->
    @handlers.onlogout()
}
