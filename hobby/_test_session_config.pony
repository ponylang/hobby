use "pony_test"

primitive \nodoc\ _TestSessionConfigList
  fun tests(test: PonyTest) =>
    test(_TestSessionConfigValidDefault)
    test(_TestSessionConfigInvalidName)
    test(_TestSessionConfigCustomName)
    test(_TestSessionConfigCustomMaxAge)

class \nodoc\ iso _TestSessionConfigValidDefault is UnitTest
  fun name(): String => "SessionConfig/valid-default"

  fun apply(h: TestHelper) =>
    let store = MemorySessionStore
    try
      let key = CookieSigningKey.generate()?
      SessionConfig(key, store)?
    else
      h.fail("valid default config should not error")
    end
    store.dispose()

class \nodoc\ iso _TestSessionConfigInvalidName is UnitTest
  fun name(): String => "SessionConfig/invalid-name"

  fun apply(h: TestHelper) =>
    let store = MemorySessionStore
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); store.dispose(); return
      end
    try
      // Cookie names with spaces are invalid
      SessionConfig(key, store where cookie_name' = "bad name")?
      h.fail("invalid name should error")
    end
    store.dispose()

class \nodoc\ iso _TestSessionConfigCustomName is UnitTest
  fun name(): String => "SessionConfig/custom-name"

  fun apply(h: TestHelper) =>
    let store = MemorySessionStore
    try
      let key = CookieSigningKey.generate()?
      let config = SessionConfig(key, store
        where cookie_name' = "_hobby_session")?
      h.assert_eq[String]("_hobby_session", config.cookie_name)
    else
      h.fail("custom name without __Host- should succeed")
    end
    store.dispose()

class \nodoc\ iso _TestSessionConfigCustomMaxAge is UnitTest
  fun name(): String => "SessionConfig/custom-max-age"

  fun apply(h: TestHelper) =>
    let store = MemorySessionStore
    try
      let key = CookieSigningKey.generate()?
      let config = SessionConfig(key, store where max_age' = 3600)?
      match config.max_age
      | let ma: I64 => h.assert_eq[I64](3600, ma)
      else h.fail("max_age should be 3600")
      end
    else
      h.fail("config with max_age should succeed")
    end
    store.dispose()
