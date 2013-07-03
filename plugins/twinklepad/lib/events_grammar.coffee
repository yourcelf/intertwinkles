logger = require("log4js").getLogger()
base_events_grammar = require("../../../lib/base_events_grammar.coffee")

module.exports = {
  get_terms: (event) ->
    return null unless event.application == "twinklepad"
    switch event.type
      when "create"
        return [{
          entity: "Pad"
          aspect: "\"#{event.data.entity_name}\""
          collective: "new pads"
          verbed: "created"
          manner: ""
        }]
      when "update"
        return [{
          entity: event.data.entity_name
          aspect: "text"
          collective: "changed pads"
          verbed: "changed"
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

    matched = base_events_grammar.get_terms(event)
    if matched?
      return matched
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
