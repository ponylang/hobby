use "collections"

class val SessionData
  """
  An immutable snapshot of session state.

  Sent from `MemorySessionStore` to the connection after a session load.
  String keys and string values — stringly-typed session data forces explicit
  serialization at the boundary, matching the standard approach (Phoenix,
  Rails, Flask).

  The `is_new` flag distinguishes freshly created sessions (no matching
  cookie, invalid cookie, or ID not found in store) from sessions loaded
  from the store.
  """
  let _id: String val
  let _data: Map[String, String] val
  let _is_new: Bool

  new val _create(id': String val, data': Map[String, String] val,
    is_new': Bool = false)
  =>
    _id = id'
    _data = data'
    _is_new = is_new'

  new val _empty(id': String val) =>
    """Create an empty session marked as new."""
    _id = id'
    _data = recover val Map[String, String] end
    _is_new = true

  fun id(): String val =>
    """Return the session identifier."""
    _id

  fun is_new(): Bool =>
    """
    Return `true` if this session was freshly created rather than loaded
    from the store.
    """
    _is_new

  fun apply(key: String): String val ? =>
    """Get a session value by key. Errors if absent."""
    _data(key)?

  fun get_or(key: String, default: String val): String val =>
    """Get a session value, returning `default` if absent."""
    try _data(key)? else default end

  fun contains(key: String): Bool =>
    """Return `true` if the key exists in the session."""
    _data.contains(key)

  fun pairs(): MapPairs[String, String, HashEq[String],
    Map[String, String] val]^
  =>
    """Return an iterator over the session key-value pairs."""
    _data.pairs()

  fun size(): USize =>
    """Return the number of key-value pairs."""
    _data.size()
