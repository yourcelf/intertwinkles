module.exports = {
  get_terms: (event) ->
    switch event.type
      when "deletion"
        return [{
          entity: event.data.entity_name
          aspect: ""
          collective: "removals"
          verbed: "deletion requested"
          manner: ""
        }]
      when "undeletion"
        return [{
          entity: event.data.entity_name
          aspect: ""
          collective: "removals"
          verbed: "deletion cancelled"
          manner: ""
        }]
      when "trash"
        return [{
          entity: event.data.entity_name
          aspect: ""
          collective: "removals"
          verbed: "moved to trash"
          manner: ""
        }]
      when "untrash"
        return [{
          entity: event.data.entity_name
          aspect: ""
          collective: "removals"
          verbed: "restored from trash"
          manner: ""
        }]
    return null
}
