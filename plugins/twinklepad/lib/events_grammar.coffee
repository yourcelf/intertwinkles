logger = require("log4js").getLogger()

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
          aspect: "pad"
          collective: "visited pads"
          verbed: "visited"
          manner: ""
        }]
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
