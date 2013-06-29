logger = require("log4js").getLogger()
module.exports = {
  get_terms: (event) ->
    return null unless event.application == "points"
    switch event.type
      when "create"
        return [{
          entity: "Points of Unity"
          aspect: "\"#{event.data.entity_name}\""
          collective: "created points of unity"
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
        for key in ["name", "slug"]
          if event.data[key]?
            attributes.push({
              entity: if key == "name" then "Points of Unity" else event.data.entity_name
              aspect: key
              collective: "changed points of unity"
              verbed: "changed"
              manner: "from \"#{event.data["old_" + key]}\" to \"#{event.data[key]}\""
            })
        if event.data.sharing?
          attributes.push({
            entity: event.data.entity_name
            aspect: "sharing settings"
            collective: "changed points of unity"
            verbed: "changed"
            manner: ""
          })
        return attributes
      when "append"
        if event.data.is_new
          return [{
            entity: event.data.entity_name
            aspect: "point"
            collective: "added points"
            verbed: "added"
            manner: event.data.text
          }]
        else
          return [{
            entity: event.data.entity_name
            aspect: "point"
            collective: "edited points"
            verbed: "edited"
            manner: event.data.text
          }]
      when "vote"
        return [{
          entity: event.data.entity_name
          aspect: "vote"
          collective: "votes"
          verbed: if event.data.support then "added" else "removed"
          manner: event.data.text
        }]
      when "approve"
        return [{
          entity: event.data.entity_name
          aspect: "point"
          collective: "adopted points"
          verbed: if event.data.approve then "adopted" else "retired"
          manner: event.data.text
        }]
      when "trash_point"
        return [{
          entity: event.data.entity_name
          aspect: "point"
          collective: "points moved to trash"
          verbed: "moved to trash"
          manner: event.data.text
        }]
      when "untrash_point"
        return [{
          entity: event.data.entity_name
          aspect: "point"
          collective: "points restored from trash"
          verbed: "restored from trash"
          manner: event.data.text
        }]
      when "deletion"
        return [{
          entity: event.data.entity_name
          aspect: "point set"
          collective: "requests to delete"
          verbed: "requested deletion"
          manner: "by #{event.data.end_date.toString()}"
        }]
      when "undeletion"
        return [{
          entity: event.data.entity_name
          aspect: "point set"
          collective: "cancelled deletions"
          verbed: "cancelled deletion"
          manner: ""
        }]
      when "trash"
        return [{
          entity: event.data.entity_name
          aspect: "point set"
          collective: "moved to trash"
          verbed: "moved to trash"
          manner: ""
        }]
      when "untrash"
        return [{
          entity: event.data.entity_name
          aspect: "point set"
          collective: "restored from trash"
          verbed: "restored from trash"
          manner: ""
        }]
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
