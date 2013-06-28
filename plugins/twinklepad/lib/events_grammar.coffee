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
          aspect: ""
          collective: "visits"
          verbed: "visited"
          manner: ""
        }]
      when "deletion"
        return [{
          entity: event.data.entity_name
          aspect: "twinklepad"
          collective: "requests to delete"
          verbed: "requested deletion"
          manner: "by #{event.data.end_date.toString()}"
        }]
      when "undeletion"
        return [{
          entity: event.data.entity_name
          aspect: "twinklepad"
          collective: "cancelled deletions"
          verbed: "cancelled deletion"
          manner: ""
        }]
      when "trash"
        return [{
          entity: event.data.entity_name
          aspect: "twinklepad"
          collective: "moved to trash"
          verbed: "moved to trash"
          manner: ""
        }]
      when "untrash"
        return [{
          entity: event.data.entity_name
          aspect: "twinklepad"
          collective: "restored from trash"
          verbed: "restored from trash"
          manner: ""
        }]
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
