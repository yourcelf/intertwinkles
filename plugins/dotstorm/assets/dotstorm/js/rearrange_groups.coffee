root = this

uuid = (a) ->
  # Generate a uuid: https://gist.github.com/982883
  if a
    return (a^Math.random() * 16 >> a / 4).toString(16)
  else
    return ([1e7] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, uuid)

create_group = (idea_id) ->
  return {_id: uuid(), ideas: [idea_id]}

#
# Moving ideas within/between/into groups.
# 
# Movement is a list of 5 arguments:
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
rearrange = (groups, trash, movement) ->
  return false unless verify_rearrange_args(groups, trash, movement)
  [sourceGroupPos, sourceIdeaPos, destGroupPos, destIdeaPos, offset] = movement
  offset ?= 0
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
  else if sourceGroupPos == null
    # MOVING OUT OF TRASH.  Source group is null.
    id = trash.splice(sourceIdeaPos, 1)[0]
    pos = groups.length
    groups.splice(pos, 0, create_group(id))
    # Is this our desired destination?
    if destGroupPos + offset == pos and destIdeaPos == null
      return [groups, trash]
    # If not, Just recurse to avoid duplicating the logic for moving.
    rearrange(groups, trash, [pos, 0, destGroupPos, destIdeaPos, offset])
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
      return [groups, trash]
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
        newGroup = create_group(source)
        groups.splice(destGroupPos + destGroupOffset + offset, 0, newGroup)
      else
        # Dest is within the target group.
        destGroup.ideas.splice(destIdeaPos + offset, 0, source)
    return [groups, trash]

verify_rearrange_args = (groups, trash, movement) ->
  [sourceGroupPos, sourceIdeaPos, destGroupPos, destIdeaPos, offset] = movement
  return false unless offset == 0 or offset == 1
  if sourceGroupPos == null
    # Source is trash; but null sourceIdeaPos implies moving group. Can't move
    # the "group" trash.
    return false if sourceIdeaPos == null
    # Source idea pos must be within trash limits.
    return false unless 0 <= sourceIdeaPos < trash.length
  else
    # Source is not trash.
    return false unless 0 <= sourceGroupPos < groups.length
    if sourceIdeaPos != null
      return false unless 0 <= sourceIdeaPos < groups[sourceGroupPos].ideas.length
  if destGroupPos == null
    # Dest is trash. Must drop within trash. Will default to 0 if destIdeaPos is null.
    return false unless (destIdeaPos == null) or (0 <= destIdeaPos <= trash.length)
  else
    # Dest is not trash.
    return false unless 0 <= destGroupPos <= groups.length
    return false unless (
        (destIdeaPos == null) or (0 <= destIdeaPos <= groups[destGroupPos].ideas.length)
    )
  return true

# Put ourselves in the global namespace of browsers, or as the export for a
# node module
to_export = { rearrange, uuid, create_group, verify_rearrange_args }
if typeof module != 'undefined'
  module.exports = to_export
else if typeof window != 'undefined'
  window.dotstorm_rearranger = to_export
