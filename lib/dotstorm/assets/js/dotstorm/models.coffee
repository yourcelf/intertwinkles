_.extend Backbone.Model.prototype, {
  # Use mongodb id attribute
  idAttribute: '_id'
}

class ds.Idea extends Backbone.Model
  collectionName: 'Idea'
  cleanTags: (commaStr) ->
    rawtags = commaStr.split(/,\s*/)
    clean = []
    for tag in rawtags
      if tag != ""
        clean.push($.trim(tag.replace(/[^-\w\s]/g, '')))
    return clean



class ds.IdeaList extends Backbone.Collection
  model: ds.Idea
  collectionName: ds.Idea.prototype.collectionName

class ds.Dotstorm extends Backbone.Model
  collectionName: 'Dotstorm'
  defaults:
    groups: []
  slugify: (name) -> return name.toLowerCase().replace(/[^a-z0-9_\.]/g, '-')
  uuid: (a) =>
    # Generate a uuid: https://gist.github.com/982883
    if a
      return (a^Math.random() * 16 >> a / 4).toString(16)
    else
      return ([1e7] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, @uuid)


  validate: (attrs) ->
    if attrs.slug?.length < 4
      return "Name must be 4 or more characters."

  indexOfIdeaId: (idea_id, _list, _parent, _group_pos) =>
    groups = @get("groups") or []
    pos = i = -1
    for i in [0...groups.length]
      pos = _.indexOf groups[i].ideas, idea_id
      if pos != -1
        return [i, pos]
    return null

  #
  # Adding and removing ideas
  #

  addIdea: (idea, options) => @addIdeaId idea.id, options
  addIdeaId: (idea_id, options) =>
    unless @indexOfIdeaId(idea_id)?
      groups = @get("groups") or []
      groups.splice(0, 0, @createGroup(idea_id))
      @set("groups", groups, options)
  createGroup: (idea_id) =>
    return {_id: @uuid(), ideas: [idea_id]}
  removeIdea: (idea, options) => @removeIdeaId(idea.id, options)
  removeIdeaId: (idea_id, options) =>
    pos = @indexOfIdeaId(idea_id)
    if pos?
      groups = @get("groups")
      if groups[pos[0]].ideas.length == 1
        groups.splice(pos[0], 1)
      else
        groups[pos[0]].ideas.splice(pos[1], 1)
      @orderChanged(options)

  #
  # Moving ideas within/between/into groups.
  # 
  # Takes 4 arguments:
  #   sourceGroupPos: the source group position (or null if the source is in
  #                   the trash).
  #   sourceIdeaPos: the position of the idea within the source group, or null
  #                  if the whole group is being moved.
  #   destGroupPos: the position of the group at the destination (or null if
  #                 the destination is the trash).
  #   destIdeaPos: the position of the idea within the group into which to
  #                interpolate the source idea(s); or null, if we intend to 
  #                drop the source idea(s) adjacent the destination group.
  #   offset: positional offset. 0 for left side, 1 for right side.
  move: (sourceGroupPos, sourceIdeaPos, destGroupPos, destIdeaPos, offset=0) =>
    groups = @get("groups")
    trash = @get("trash") or []
    finish = =>
      @orderChanged()
      @set("groups", groups)
    if destGroupPos == null
      # MOVING TO TRASH.  Dest group is null.
      if sourceIdeaPos == null
        # Move whole group to the trash.
        group = groups.splice(sourceGroupPos, 1)[0]
        toTrash = group.ideas
      else
        # Move individual note to trash.
        toTrash = groups[sourceGroupPos].ideas.splice(sourceIdeaPos, 1)
        if groups[sourceGroupPos].ideas.length == 0
          groups.splice(sourceGroupPos, 1)
      trash.splice.apply(trash, [destIdeaPos or 0, 0].concat(toTrash))
      @set("trash", trash)
    else if sourceGroupPos == null
      # MOVING OUT OF TRASH.  Source group is null.
      id = trash.splice(sourceIdeaPos, 1)[0]
      pos = groups.length
      groups.splice(pos, 0, @createGroup(id))
      # Is this our desired destination?
      if destGroupPos + offset == pos and destIdeaPos == null
        return
      # If not, Just recurse to avoid duplicating the logic for moving.
      @move(pos, 0, destGroupPos, destIdeaPos, offset)
    else if sourceIdeaPos == null
      # MOVING A GROUP: Source is a whole group.
      # Ignore move if we're moving a group to itself.
      unless destGroupPos == sourceGroupPos
        # Source is a whole group.
        source = groups.splice(sourceGroupPos, 1)[0]
        destGroupOffset = if destGroupPos < sourceGroupPos then 0 else -1
        if destIdeaPos == null
          # Dest is adjacent the target group.
          groups.splice(destGroupPos + destGroupOffset + offset, 0, source)
        else
          # Dest is inside a target group.
          dest = groups[destGroupPos + destGroupOffset]
          dest.ideas.splice.apply(dest.ideas,
            [destIdeaPos + offset, 0].concat(source.ideas))
          if source.label? and not dest.label?
            dest.label = source.label
        return finish()
    else
      # MOVING AN IDEA: Source is a member of a group.
      if sourceGroupPos == destGroupPos and destIdeaPos != null
        group = groups[sourceGroupPos]
        destOffset = if destIdeaPos < sourceIdeaPos then 0 else -1
        idea = group.ideas.splice(sourceIdeaPos, 1)[0]
        group.ideas.splice(destIdeaPos + destOffset + offset, 0, idea)
      else
        # Moving between groups.
        source = groups[sourceGroupPos].ideas.splice(sourceIdeaPos, 1)[0]
        if groups[sourceGroupPos].ideas.length == 0
          groups.splice(sourceGroupPos, 1)
          destGroupOffset = if destGroupPos < sourceGroupPos then 0 else -1
        else
          destGroupOffset = 0
        destGroup = groups[destGroupPos + destGroupOffset]
        if destIdeaPos == null
          # Dest is adjacent the target group.
          newGroup = @createGroup(source)
          groups.splice(destGroupPos + destGroupOffset + offset, 0, newGroup)
        else
          # Dest is within the target group.
          destGroup.ideas.splice(destIdeaPos + offset, 0, source)
      return finish()

  orderChanged: (options) => @trigger "change:ideas" unless options?.silent


class ds.DotstormList extends Backbone.Collection
  model: ds.Dotstorm
  collectionName: ds.Dotstorm.prototype.collectionName

modelFromCollectionName = (collectionName, isCollection=false) ->
  if isCollection
    switch collectionName
      when "Idea" then ds.IdeaList
      when "Dotstorm" then ds.DotstormList
      else null
  else
    switch collectionName
      when "Idea" then ds.Idea
      when "Dotstorm" then ds.Dotstorm
      else null

