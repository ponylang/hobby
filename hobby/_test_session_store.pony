use "collections"
use "pony_test"
use "time"

primitive \nodoc\ _TestSessionStoreList
  fun tests(test: PonyTest) =>
    test(_TestSessionStoreSaveLoad)
    test(_TestSessionStoreLoadUnknown)
    test(_TestSessionStoreOverwrite)
    test(_TestSessionStoreDelete)
    test(_TestSessionStoreDeleteUnknown)
    test(_TestSessionStoreTtlExpiry)
    test(_TestSessionStoreCapacity)

// --- Mock requester ---

actor \nodoc\ _MockSessionRequester is _SessionRequester
  """
  Test actor that receives session load callbacks and checks assertions.
  Disposes the store and completes the test after the check runs.
  """
  let _h: TestHelper
  let _check: {(SessionData val, TestHelper)} val
  let _store: MemorySessionStore tag

  new create(h: TestHelper, store: MemorySessionStore tag,
    check: {(SessionData val, TestHelper)} val)
  =>
    _h = h
    _check = check
    _store = store

  be _session_loaded(session: SessionData val) =>
    _check(session, _h)
    _store.dispose()
    _h.complete(true)

// --- Helpers ---

primitive \nodoc\ _TestSessionStoreHelper
  fun session_with(id: String val,
    pairs: Array[(String val, String val)] val): SessionData val
  =>
    let m: Map[String, String] iso = recover iso Map[String, String] end
    for (k, v) in pairs.values() do
      m(k) = v
    end
    SessionData._create(id, consume m)

// --- Tests ---

class \nodoc\ iso _TestSessionStoreSaveLoad is UnitTest
  fun name(): String => "SessionStore/save-load"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let store = MemorySessionStore
    let session = _TestSessionStoreHelper.session_with("s1",
      [("user", "alice")])
    store.save(session)
    let check = {(loaded: SessionData val, h': TestHelper) =>
      try
        h'.assert_eq[String]("alice", loaded("user")?)
      else
        h'.fail("key not found")
      end
      h'.assert_false(loaded.is_new())
      h'.assert_eq[String]("s1", loaded.id())
    } val
    store.load("s1", _MockSessionRequester(h, store, check))

class \nodoc\ iso _TestSessionStoreLoadUnknown is UnitTest
  fun name(): String => "SessionStore/load-unknown"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let store = MemorySessionStore
    let check = {(loaded: SessionData val, h': TestHelper) =>
      h'.assert_true(loaded.is_new())
      h'.assert_eq[String]("unknown-id", loaded.id())
      h'.assert_eq[USize](0, loaded.size())
    } val
    store.load("unknown-id", _MockSessionRequester(h, store, check))

class \nodoc\ iso _TestSessionStoreOverwrite is UnitTest
  fun name(): String => "SessionStore/overwrite"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let store = MemorySessionStore
    let session1 = _TestSessionStoreHelper.session_with("s1",
      [("user", "alice")])
    let session2 = _TestSessionStoreHelper.session_with("s1",
      [("user", "bob")])
    store.save(session1)
    store.save(session2)
    let check = {(loaded: SessionData val, h': TestHelper) =>
      try
        h'.assert_eq[String]("bob", loaded("user")?)
      else
        h'.fail("key not found")
      end
    } val
    store.load("s1", _MockSessionRequester(h, store, check))

class \nodoc\ iso _TestSessionStoreDelete is UnitTest
  fun name(): String => "SessionStore/delete"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let store = MemorySessionStore
    let session = _TestSessionStoreHelper.session_with("s1",
      [("user", "alice")])
    store.save(session)
    store.delete("s1")
    let check = {(loaded: SessionData val, h': TestHelper) =>
      h'.assert_true(loaded.is_new(), "deleted session should appear as new")
      h'.assert_eq[USize](0, loaded.size())
    } val
    store.load("s1", _MockSessionRequester(h, store, check))

class \nodoc\ iso _TestSessionStoreDeleteUnknown is UnitTest
  fun name(): String => "SessionStore/delete-unknown"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let store = MemorySessionStore
    // Delete a non-existent session — should not error
    store.delete("absent")
    // Verify store still works by loading
    let check = {(loaded: SessionData val, h': TestHelper) =>
      h'.assert_true(loaded.is_new())
    } val
    store.load("absent", _MockSessionRequester(h, store, check))

class \nodoc\ iso _TestSessionStoreTtlExpiry is UnitTest
  """
  Sessions expire when their TTL is exceeded. Uses a 1-second TTL and
  a 2-second delayed load to verify the lazy expiry check in `load`.
  """
  fun name(): String => "SessionStore/ttl-expiry"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let store = MemorySessionStore(10_000, 1)
    let session = _TestSessionStoreHelper.session_with("s1",
      [("user", "alice")])
    store.save(session)
    let check = {(loaded: SessionData val, h': TestHelper) =>
      h'.assert_true(loaded.is_new(), "expired session should appear as new")
      h'.assert_eq[USize](0, loaded.size())
    } val
    let requester = _MockSessionRequester(h, store, check)
    // Delay the load by 2 seconds to allow TTL to expire
    let timers = Timers
    let timer = Timer(
      _DelayedLoadNotify(store, "s1", requester, timers), 2_000_000_000, 0)
    timers(consume timer)

class \nodoc\ iso _TestSessionStoreCapacity is UnitTest
  """
  When the store reaches max_sessions, new sessions are silently dropped.
  Existing sessions remain retrievable.
  """
  fun name(): String => "SessionStore/capacity"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let store = MemorySessionStore(2, 1800)
    let s1 = _TestSessionStoreHelper.session_with("s1",
      [("user", "alice")])
    let s2 = _TestSessionStoreHelper.session_with("s2",
      [("user", "bob")])
    let s3 = _TestSessionStoreHelper.session_with("s3",
      [("user", "charlie")])
    store.save(s1)
    store.save(s2)
    store.save(s3)  // Should be silently dropped
    // Verify s3 was dropped (loads as new empty session)
    let check_s3 = {(loaded: SessionData val, h': TestHelper) =>
      h'.assert_true(loaded.is_new(), "s3 should be new (dropped)")
    } val
    // Verify s1 is still there
    let check_s1 = {(loaded: SessionData val, h': TestHelper)(store) =>
      try
        h'.assert_eq[String]("alice", loaded("user")?)
      else
        h'.fail("s1 data lost")
      end
      // Now check s3 in a chained load
      let inner_check = {(loaded': SessionData val, h'': TestHelper) =>
        h''.assert_true(loaded'.is_new(), "s3 should be new (dropped)")
      } val
      store.load("s3", _MockSessionRequester(h', store, inner_check))
    } val
    store.load("s1", _CapacityCheckRequester(h, store, check_s1))

// --- Timer support for TTL test ---

class \nodoc\ iso _DelayedLoadNotify is TimerNotify
  """Fires once to trigger a delayed session load."""
  let _store: MemorySessionStore tag
  let _session_id: String val
  let _requester: _SessionRequester tag
  let _timers: Timers

  new iso create(store: MemorySessionStore tag, session_id: String val,
    requester: _SessionRequester tag, timers: Timers)
  =>
    _store = store
    _session_id = session_id
    _requester = requester
    _timers = timers

  fun ref apply(timer: Timer, count: U64): Bool =>
    _store.load(_session_id, _requester)
    _timers.dispose()
    false

  fun ref cancel(timer: Timer) => None

// Requester that doesn't dispose the store (for chained loads)
actor \nodoc\ _CapacityCheckRequester is _SessionRequester
  let _h: TestHelper
  let _store: MemorySessionStore tag
  let _check: {(SessionData val, TestHelper)} val

  new create(h: TestHelper, store: MemorySessionStore tag,
    check: {(SessionData val, TestHelper)} val)
  =>
    _h = h
    _store = store
    _check = check

  be _session_loaded(session: SessionData val) =>
    _check(session, _h)
