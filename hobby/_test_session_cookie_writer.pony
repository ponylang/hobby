use "pony_test"
use "pony_check"

primitive \nodoc\ _TestSessionCookieWriterList
  fun tests(test: PonyTest) =>
    test(_TestSessionCookieWriterSet)
    test(_TestSessionCookieWriterClear)
    test(_TestSessionCookieWriterMaxAge)
    test(_TestSessionCookieWriterSecurityAttributes)
    test(Property1UnitTest[USize](_PropSessionCookieWriterContainsName))

// --- Helper ---

primitive \nodoc\ _TestCookieWriterHelper
  fun make_config(h: TestHelper,
    cookie_name: String val = "_test_session",
    max_age: (I64 | None) = None)
    : (SessionConfig, MemorySessionStore tag) ?
  =>
    let store = MemorySessionStore
    let key = CookieSigningKey.generate()?
    let config = SessionConfig(key, store
      where cookie_name' = cookie_name, max_age' = max_age)?
    (config, store)

// --- Example-based tests ---

class \nodoc\ iso _TestSessionCookieWriterSet is UnitTest
  fun name(): String => "SessionCookieWriter/set"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestCookieWriterHelper.make_config(h)?
      else h.fail("setup failed"); return
      end
    let header = _SessionCookieWriter.set_cookie(config, "session-123")
    h.assert_true(header.size() > 0, "header should not be empty")
    h.assert_true(header.contains("_test_session="),
      "should contain cookie name")
    h.assert_true(header.contains("Path=/"),
      "should contain path")
    // The value should contain a signed cookie (has a dot separator)
    h.assert_true(header.contains("."),
      "cookie value should be signed (contains dot)")
    store.dispose()

class \nodoc\ iso _TestSessionCookieWriterClear is UnitTest
  fun name(): String => "SessionCookieWriter/clear"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestCookieWriterHelper.make_config(h)?
      else h.fail("setup failed"); return
      end
    let header = _SessionCookieWriter.clear_cookie(config)
    h.assert_true(header.size() > 0, "header should not be empty")
    h.assert_true(header.contains("Max-Age=0"),
      "should contain Max-Age=0")
    h.assert_true(header.contains("_test_session="),
      "should contain cookie name")
    store.dispose()

class \nodoc\ iso _TestSessionCookieWriterMaxAge is UnitTest
  fun name(): String => "SessionCookieWriter/max-age"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestCookieWriterHelper.make_config(h
        where max_age = 3600)?
      else h.fail("setup failed"); return
      end
    let header = _SessionCookieWriter.set_cookie(config, "session-123")
    h.assert_true(header.contains("Max-Age=3600"),
      "should contain Max-Age=3600")
    store.dispose()

class \nodoc\ iso _TestSessionCookieWriterSecurityAttributes is UnitTest
  fun name(): String => "SessionCookieWriter/security-attributes"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestCookieWriterHelper.make_config(h)?
      else h.fail("setup failed"); return
      end
    let header = _SessionCookieWriter.set_cookie(config, "session-123")
    h.assert_true(header.contains("Secure"),
      "should contain Secure")
    h.assert_true(header.contains("HttpOnly"),
      "should contain HttpOnly")
    h.assert_true(header.contains("SameSite=Lax"),
      "should contain SameSite=Lax")
    store.dispose()

// --- Property-based tests ---

class \nodoc\ iso _PropSessionCookieWriterContainsName is Property1[USize]
  """
  For any generated session ID, the Set-Cookie header always contains
  the configured cookie name.
  """

  fun name(): String => "SessionCookieWriter/prop-contains-name"

  fun gen(): Generator[USize] =>
    Generators.usize(0, 100)

  fun property(sample: USize, h: PropertyHelper) =>
    let store = MemorySessionStore
    try
      let key = CookieSigningKey.generate()?
      let config = SessionConfig(key, store
        where cookie_name' = "_test_session")?
      let session_id = SessionId.generate()?
      let header = _SessionCookieWriter.set_cookie(config, session_id)
      h.assert_true(header.contains("_test_session="),
        "header must contain cookie name")
    else
      h.fail("setup failed")
    end
    store.dispose()
