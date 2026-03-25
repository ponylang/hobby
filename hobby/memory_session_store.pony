use "collections"
use "time"

actor MemorySessionStore
  """
  An in-memory session store with eviction.

  Sessions are stored in a `HashMap` keyed by session ID. Eviction uses two
  strategies:

  - **TTL-based**: Sessions not accessed within `ttl_seconds` are expired.
    A periodic sweep removes expired sessions. `load` also checks expiry
    lazily.
  - **Count-based**: The store will not exceed `max_sessions` entries. New
    sessions are silently dropped when at capacity (TTL sweep recovers
    capacity over time).

  Eviction is required — without it, cookieless requests (bots, health
  checks, curl) create unbounded growth.

  `save` is fire-and-forget. Pony's causal messaging guarantees FIFO per
  sender-receiver pair: a save from connection A is visible to a subsequent
  load from connection A.

  Server restart loses all sessions. Callers must call `dispose()` for clean
  shutdown — the internal sweep timer keeps the actor alive indefinitely.
  """
  embed _sessions: HashMap[String, _StoredSession, HashEq[String]]
  let _max_sessions: USize
  let _ttl_ns: U64
  let _timers: Timers

  new create(max_sessions: USize = 10_000,
    ttl_seconds: U64 = 1800)
  =>
    """
    Create a session store.

    `max_sessions` bounds memory (default 10,000). `ttl_seconds` is the
    inactivity TTL (default 30 minutes). A sweep timer runs at `ttl/2`
    intervals (minimum 60 seconds).
    """
    _sessions = HashMap[String, _StoredSession, HashEq[String]]
    _max_sessions = max_sessions
    _ttl_ns = ttl_seconds * 1_000_000_000
    _timers = Timers
    let half = ttl_seconds / 2
    let sweep_ns: U64 =
      if half < 60 then 60_000_000_000
      else half * 1_000_000_000
      end
    let timer = Timer(_SweepNotify(this), sweep_ns, sweep_ns)
    _timers(consume timer)

  be load(session_id: String val, requester: _SessionRequester tag) =>
    """
    Look up a session by ID. If found and not expired, delivers it. If
    not found or expired, delivers an empty session marked as new.
    """
    try
      let stored = _sessions(session_id)?
      let now = Time.nanos()
      if (now - stored.last_accessed) > _ttl_ns then
        try _sessions.remove(session_id)? end
        requester._session_loaded(SessionData._empty(session_id))
      else
        stored.last_accessed = now
        requester._session_loaded(stored.data)
      end
    else
      requester._session_loaded(SessionData._empty(session_id))
    end

  be save(session: SessionData val) =>
    """
    Save a session. Fire-and-forget. Updates always succeed. New sessions
    are silently dropped when at capacity.
    """
    let id = session.id()
    if _sessions.contains(id) then
      _sessions(id) = _StoredSession(session, Time.nanos())
    else
      if _sessions.size() < _max_sessions then
        _sessions(id) = _StoredSession(session, Time.nanos())
      end
    end

  be delete(session_id: String val) =>
    """Remove a session. No-op if absent."""
    try _sessions.remove(session_id)? end

  be _sweep() =>
    """Remove all expired sessions."""
    let now = Time.nanos()
    let expired = Array[String]
    for (id, stored) in _sessions.pairs() do
      if (now - stored.last_accessed) > _ttl_ns then
        expired.push(id)
      end
    end
    for id in expired.values() do
      try _sessions.remove(id)? end
    end

  be dispose() =>
    """Cancel the sweep timer."""
    _timers.dispose()

class ref _StoredSession
  """Session entry with access tracking for TTL eviction."""
  let data: SessionData val
  var last_accessed: U64

  new ref create(data': SessionData val, last_accessed': U64) =>
    data = data'
    last_accessed = last_accessed'

class iso _SweepNotify is TimerNotify
  """Timer notify that triggers eviction sweeps."""
  let _store: MemorySessionStore tag

  new iso create(store: MemorySessionStore tag) =>
    _store = store

  fun ref apply(timer: Timer, count: U64): Bool =>
    _store._sweep()
    true

  fun ref cancel(timer: Timer) => None
