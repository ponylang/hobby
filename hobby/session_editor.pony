use "collections"

class ref SessionEditor
  """
  A mutable editor for session data within a single request.

  Created inside the `recover iso` block for `HandlerContext` from a loaded
  `SessionData val`. The handler reads and writes through this editor via
  `RequestHandler.session()`.

  After the handler responds, `RequestHandler` calls `_finish()` to produce
  a new `SessionData val` and bundles the mutation metadata into a
  `_SessionResult val` that travels back to `_Connection` via the protocol.

  Call `regenerate_id()` after login to prevent session fixation. Call
  `mark_for_deletion()` for logout.

  **Known limitation: `regenerate_id()` and concurrent requests.** If
  request A calls `regenerate_id()` while request B (same session, different
  connection) is in flight, B can save with the old ID after A deleted it.
  This is inherent to optimistic concurrent sessions without locking.

  **Known limitation: `regenerate_id()` during streaming.** Once headers are
  on the wire, the new cookie cannot be sent. The old session is deleted, the
  new one is saved, but the client keeps the old (now-deleted) ID. Next
  request gets a fresh empty session. Avoid calling `regenerate_id()` during
  streaming.
  """
  let _original: SessionData val
  embed _data: Map[String, String]
  var _id: String val
  var _previous_id: (String val | None) = None
  var _modified: Bool = false
  var _deleted: Bool = false

  new ref _create(session: SessionData val) =>
    _original = session
    _id = session.id()
    _data = Map[String, String](session.size())
    for (k, v) in session.pairs() do
      _data(k) = v
    end

  fun id(): String val =>
    """Return the current session identifier."""
    _id

  fun apply(key: String): String val ? =>
    """Get a session value by key. Errors if absent."""
    _data(key)?

  fun get_or(key: String, default: String val): String val =>
    """Get a session value, returning `default` if absent."""
    try _data(key)? else default end

  fun contains(key: String): Bool =>
    """Return `true` if the key exists in the session."""
    _data.contains(key)

  fun ref set(key: String, value: String val) =>
    """Set a session value. Marks the session as modified."""
    _data(key) = value
    _modified = true

  fun ref remove(key: String) =>
    """Remove a key from the session. Marks the session as modified."""
    try _data.remove(key)? end
    _modified = true

  fun ref regenerate_id() ? =>
    """
    Generate a new session ID, preserving all data.

    Stashes the old ID so the connection can delete it from the store.
    Errors if the CSPRNG fails.
    """
    let old = _id
    _id = SessionId.generate()?
    _previous_id = old
    _modified = true

  fun ref mark_for_deletion() =>
    """Flag this session for removal (logout path)."""
    _deleted = true

  fun ref _finish(): SessionData val =>
    """Produce a new immutable snapshot from current editor state."""
    let sz = _data.size()
    let m: Map[String, String] iso =
      recover iso Map[String, String](sz) end
    for (k, v) in _data.pairs() do
      m(k) = v
    end
    SessionData._create(_id, consume m)

  fun _is_modified(): Bool => _modified
  fun _is_deleted(): Bool => _deleted
  fun _is_new(): Bool => _original.is_new()
  fun _get_previous_id(): (String val | None) => _previous_id
