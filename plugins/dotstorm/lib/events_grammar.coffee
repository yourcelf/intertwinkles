logger = require("log4js").getLogger()
base_events_grammar = require("../../../lib/base_events_grammar.coffee")

module.exports = {
  get_terms: (event) ->
    return null unless event.application == "dotstorm"
    switch event.type
      when "create"
        return [{
          entity: "Dotstorm"
          aspect: "\"#{event.data.entity_name}\""
          collective: "created dotstorms"
          verbed: "created"
          manner: ""
        }]
      when "visit"
        return [{
          entity: event.data.entity_name
          aspect: ""
          collective: "visits"
          verbed: "visited"
          manner: ""
        }]
      when "update"
        attributes = []
        for key in ["name", "topic"]
          if event.data[key]?
            attributes.push({
              entity: event.data.entity_name
              aspect: key
              collective: "changed dotstorms"
              verbed: "changed"
              manner: "from \"#{event.data["old_" + key]}\" to \"#{event.data[key]}\""
            })
        if event.data.sharing?
          attributes.push({
            entity: event.data.entity_name
            aspect: "sharing settings"
            collective: "changed dotstorms"
            verbed: "changed"
            manner: ""
          })
        if event.data.rearranged?
          attributes.push({
            entity: event.data.entity_name
            aspect: "notes"
            collective: "changed dotstorms"
            verbed: "rearranged"
            manner: ""
          })
        return attributes
      when "append"
        if event.data.is_new
          return [{
            entity: event.data.entity_name
            aspect: "a note"
            collective: "added notes"
            verbed: "added"
            manner: event.data.description
            image: event.data.image
          }]
        else
          return [{
            entity: event.data.entity_name
            aspect: "a note"
            collective: "edited notes"
            verbed: "edited"
            manner: ""
            image: event.data.image
          }]
    matched = base_events_grammar.get_terms(event)
    if matched?
      return matched
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
