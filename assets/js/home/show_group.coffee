
class MembershipList extends Backbone.View
  template: _.template($("#membershipListTemplate").html())
  initialize: (options) ->
    @group = options.group
    @type = options.type or "members"

  render: =>
    @$el.html(@template({
      group: @group
      type: @type
    }))
    this


intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "www"})
  intertwinkles.build_footer($("footer"))
  $("#members").html(new MembershipList({
    group: INITIAL_DATA.group
    type: "members"
  }).render().el)
  if INITIAL_DATA.docs.length > 0
    $("#docs").html(new intertwinkles.DocumentList({docs: INITIAL_DATA.docs}).render().el)
  else
    $("#docs").html("No stuff created yet.")
  $("#events").html(new intertwinkles.RecentEventsSummary({
    collection: intertwinkles.buildEventCollection(INITIAL_DATA.events)
  }).render().el)
