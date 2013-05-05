logger = require("log4js").getLogger()

_ellipse = (string, length) ->
  if string.length > length
    return string.substring(0, length - 3) + "..."
  return string

module.exports = {
  get_terms: (event) ->
    return null unless event.application == "clock"
    switch event.type
      when "create"
        return [{
          entity: "Progressive Clock"
          aspect: "\"#{event.data.entity_name}\""
          collective: "new clocks"
          verbed: "created"
          manner: ""
        }]
      when "update"
        attributes = []
        if event.data.name?
          attributes.push {
            entity: "Clock"
            aspect: "name"
            collective: "changed clocks"
            verbed: "changed"
            manner: "from \"#{event.data.old_name}\" to \"#{event.data.name}\""
          }
        if event.data.about?
          attributes.push {
            entity: event.data.entity_name
            aspect: "about text"
            collective: "changed clocks"
            verbed: "changed"
            manner: "to \"#{_ellipse(event.data.about, 30)}\""
          }
        if event.data.categories?
          attributes.push {
            entity: event.data.entity_name
            aspect: "categories"
            collective: "changed clocks"
            verbed: "changed"
            manner: "to #{event.data.categories}"
          }
        if event.data.sharing?
          attributes.push {
            entity: event.data.entity_name
            aspect: "sharing"
            collective: "changed clocks"
            verbed: "changed"
            manner: ""
          }
        return attributes
      when "visit"
        return [{
          entity: event.data.entity_name
          aspect: ""
          collective: "visits"
          verbed: "visited"
          manner: ""
        }]
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
