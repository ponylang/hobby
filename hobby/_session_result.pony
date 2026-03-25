class val _SessionResult
  """
  Finalized session state sent from the handler back to the connection
  via protocol behaviors.

  Created by `RequestHandler` when the handler responds. Carries the
  immutable session snapshot plus metadata for persistence decisions.
  """
  let data: SessionData val
  let previous_id: (String val | None)
  let is_modified: Bool
  let is_deleted: Bool
  let is_new: Bool

  new val create(data': SessionData val, previous_id': (String val | None),
    is_modified': Bool, is_deleted': Bool, is_new': Bool)
  =>
    data = data'
    previous_id = previous_id'
    is_modified = is_modified'
    is_deleted = is_deleted'
    is_new = is_new'
