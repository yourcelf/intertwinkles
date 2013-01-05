#= require lib/jquery
#= require lib/modernizr-custom
Modernizr.load {
  test: Modernizr.history
  nope: '/js/lib/history.adapter.jquery.js'
}
