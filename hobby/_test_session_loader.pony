use "pony_test"
use "pony_check"

primitive \nodoc\ _TestSessionLoaderList
  fun tests(test: PonyTest) =>
    test(_TestSessionLoaderNoCookie)
    test(_TestSessionLoaderValid)
    test(_TestSessionLoaderTampered)
    test(_TestSessionLoaderWrongKey)
    test(_TestSessionLoaderMalformed)
    test(_TestSessionLoaderEmptyValue)
    test(Property1UnitTest[USize](_PropSessionLoaderValidCookieExtractsId))
    test(Property1UnitTest[(String, USize)](
      _PropSessionLoaderTamperDetection))

// --- Helper ---

primitive \nodoc\ _TestSessionLoaderHelper
  fun make_config(h: TestHelper): (SessionConfig, MemorySessionStore tag) ? =>
    let store = MemorySessionStore
    let key = CookieSigningKey.generate()?
    let config = SessionConfig(key, store
      where cookie_name' = "_test_session")?
    (config, store)

// --- Example-based tests ---

class \nodoc\ iso _TestSessionLoaderNoCookie is UnitTest
  fun name(): String => "SessionLoader/no-cookie"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestSessionLoaderHelper.make_config(h)?
      else h.fail("setup failed"); return
      end
    match _SessionLoader(None, config)
    | let _: String val => h.fail("should return SessionData, not String")
    | let sd: SessionData val =>
      h.assert_true(sd.is_new())
      h.assert_true(sd.id().size() > 0, "should have generated an ID")
    end
    store.dispose()

class \nodoc\ iso _TestSessionLoaderValid is UnitTest
  fun name(): String => "SessionLoader/valid"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestSessionLoaderHelper.make_config(h)?
      else h.fail("setup failed"); return
      end
    let session_id = "abc123"
    let signed = SignedCookie.sign(config.key, session_id)
    match _SessionLoader(signed, config)
    | let id: String val => h.assert_eq[String](session_id, id)
    | let _: SessionData val => h.fail("should return String, not SessionData")
    end
    store.dispose()

class \nodoc\ iso _TestSessionLoaderTampered is UnitTest
  fun name(): String => "SessionLoader/tampered"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestSessionLoaderHelper.make_config(h)?
      else h.fail("setup failed"); return
      end
    let signed = SignedCookie.sign(config.key, "session-id")
    let tampered =
      recover val
        let buf = signed.clone()
        try buf(0)? = buf(0)? xor 0xFF end
        consume buf
      end
    match _SessionLoader(tampered, config)
    | let _: String val => h.fail("should reject tampered cookie")
    | let sd: SessionData val => h.assert_true(sd.is_new())
    end
    store.dispose()

class \nodoc\ iso _TestSessionLoaderWrongKey is UnitTest
  fun name(): String => "SessionLoader/wrong-key"

  fun apply(h: TestHelper) =>
    let store = MemorySessionStore
    try
      let key1 = CookieSigningKey.generate()?
      let key2 = CookieSigningKey.generate()?
      let config = SessionConfig(key2, store
        where cookie_name' = "_test_session")?
      let signed = SignedCookie.sign(key1, "session-id")
      match _SessionLoader(signed, config)
      | let _: String val => h.fail("should reject wrong key")
      | let sd: SessionData val => h.assert_true(sd.is_new())
      end
    else
      h.fail("setup failed")
    end
    store.dispose()

class \nodoc\ iso _TestSessionLoaderMalformed is UnitTest
  fun name(): String => "SessionLoader/malformed"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestSessionLoaderHelper.make_config(h)?
      else h.fail("setup failed"); return
      end
    match _SessionLoader("noseparatorhere", config)
    | let _: String val => h.fail("should reject malformed cookie")
    | let sd: SessionData val => h.assert_true(sd.is_new())
    end
    store.dispose()

class \nodoc\ iso _TestSessionLoaderEmptyValue is UnitTest
  fun name(): String => "SessionLoader/empty-value"

  fun apply(h: TestHelper) =>
    (let config, let store) =
      try _TestSessionLoaderHelper.make_config(h)?
      else h.fail("setup failed"); return
      end
    match _SessionLoader("", config)
    | let _: String val => h.fail("should reject empty cookie value")
    | let sd: SessionData val => h.assert_true(sd.is_new())
    end
    store.dispose()

// --- Property-based tests ---

class \nodoc\ iso _PropSessionLoaderValidCookieExtractsId is
  Property1[USize]
  """
  Signing a generated ID and passing it through the loader returns
  that same ID string.
  """

  fun name(): String => "SessionLoader/prop-valid-cookie-extracts-id"

  fun gen(): Generator[USize] =>
    Generators.usize(0, 100)

  fun property(sample: USize, h: PropertyHelper) =>
    let store = MemorySessionStore
    try
      let key = CookieSigningKey.generate()?
      let config = SessionConfig(key, store
        where cookie_name' = "_test_session")?
      let session_id = SessionId.generate()?
      let signed = SignedCookie.sign(key, session_id)
      match _SessionLoader(signed, config)
      | let id: String val =>
        h.assert_eq[String](session_id, id)
      | let _: SessionData val =>
        h.fail("valid signed cookie should return String")
      end
    else
      h.fail("setup failed")
    end
    store.dispose()

class \nodoc\ iso _PropSessionLoaderTamperDetection is
  Property1[(String, USize)]
  """
  Flipping a byte in a signed cookie always produces a new session.
  """

  fun name(): String => "SessionLoader/prop-tamper-detection"

  fun gen(): Generator[(String, USize)] =>
    Generators.map2[String, USize, (String, USize)](
      Generators.ascii_printable(1, 100),
      Generators.usize(0, 200),
      {(s, i) => (s, i) })

  fun property(sample: (String, USize), h: PropertyHelper) =>
    (let value, let flip_hint) = sample
    let store = MemorySessionStore
    try
      let key = CookieSigningKey.generate()?
      let config = SessionConfig(key, store
        where cookie_name' = "_test_session")?
      let signed = SignedCookie.sign(key, value)
      if signed.size() == 0 then store.dispose(); return end
      let flip_pos = flip_hint % signed.size()
      let tampered =
        recover val
          let buf = signed.clone()
          try buf(flip_pos)? = buf(flip_pos)? xor 0xFF end
          consume buf
        end
      match _SessionLoader(tampered, config)
      | let id: String val =>
        h.fail("accepted tampered cookie as valid session ID: " + id)
      | let _: SessionData val => None
      end
    else
      h.fail("setup failed")
    end
    store.dispose()
