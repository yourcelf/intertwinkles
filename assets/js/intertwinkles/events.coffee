#= require ../vendor/d3.v3.js

intertwinkles.build_timeline = (selector, collection, formatter) ->
  timeline = new TimelineView({ collection: collection, formatter: formatter })
  $(selector).html(timeline.el)
  timeline.render()
  return timeline

class intertwinkles.Event extends Backbone.Model
class intertwinkles.EventCollection extends Backbone.Collection
  model: Event
  comparator: (r) -> return intertwinkles.parse_date(r.get("date")).getTime()

ruled_timeline_template = "
  <div class='container timeline'>
    <% for (var i = 0; i < rows.length; i++) { %>
      <div class='row-fluid ruled'>
        <div class='span2' style='text-align: right;'><%- rows[i].label %></div>
        <div class='span8' style='position: relative;'>
          <% for (var j = 0; j < rows[i].length; j++) { %>
            <% var point = rows[i][j]; %>
            <span class='timeline-bump' style='left: <%- point.left %>%'>
              <%= point.formatted %>
            </span>
          <% } %>
        </div>
      </div>
    <% } %>
    <div class='row-fluid'>
      <div class='span2'></div>
      <div class='span8 ruled' style='position: relative;'>
        <% for (var i = 0; i < ticks.length; i++) { %>
          <span class='date-legend'
                style='left: <%- ticks[i].left %>%'
                ><%- ticks[i].label %></span>
        <% } %>
      </div>
  </div>
"

class RuledTimelineView extends Backbone.View
  template:  _.template(ruled_timeline_template)

  initialize: (options) ->
    @coll = options.collection
    @formatter = options.formatter

  render: =>
    if @coll.length == 0
      @$el.html("")
      return this
    rows = []
    ticks = []
    min_date = @coll.at(0).get("date")
    min_time = min_date.getTime()
    max_date = @coll.at(@coll.length - 1).get("date")
    max_time = max_date.getTime()
    time_span = Math.max(max_time - min_time, 1)
    @coll.each (entry) =>
      type = entry.get("type")
      unless rows[type]?
        rows[type] = []
        rows[type].label = entry.get("type")
        rows.push(rows[type])
      point = {
        formatted: @formatter(entry.toJSON())
        left: 100 * (entry.get("date").getTime() - min_time) / time_span
      }
      rows[type].push(point)

    # Build timeline scale
    if time_span < 1000 * 60
      date_fmt = "h:mm:s"
      step = 1000
    else if time_span < 1000 * 60 * 60
      date_fmt = "h:mm tt"
      step = 1000 * 60
    else if time_span < 1000 * 60 * 60 * 24
      date_fmt = "h tt"
      step = 1000 * 60 * 60
    else if time_span < 1000 * 60 * 60 * 24 * 7
      date_fmt = "ddd M-d"
      step = 1000 * 60 * 60 * 24
    else if time_span < 1000 * 60 * 60 * 24 * 14
      date_fmt = "M-d"
      step = 1000 * 60 * 60 * 24
    else if time_span < 1000 * 60 * 60 * 24 * 7 * 12
      date_fmt = "MMM d"
      step = 1000 * 60 * 60 * 24 * 31
    else if time_span < 1000 * 60 * 60 * 24 * 7 * 52
      date_fmt = "MMM"
      step = 1000 * 60 * 60 * 24 * 31
    else
      date_fmt = "yyyy"
      step = 1000 * 60 * 60 * 24 * 365

    # Adjust scale. #FIXME
    while time_span / step < 2
      step /= 2
    while time_span / step > 10
      step *= 2

    ticks = []
    i = 0
    while true
      next = step * i++
      if next < time_span
        ticks.push({
          label: new Date(min_time + next).toString(date_fmt)
          left: parseInt(next / time_span * 100)
        })
      else
        break

    @$el.html @template({ rows, ticks })
    @$("[rel=popover]").popover()

TimelineView = RuledTimelineView

