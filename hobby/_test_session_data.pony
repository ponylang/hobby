use "collections"
use "pony_test"
use "pony_check"

primitive \nodoc\ _TestSessionDataList
  fun tests(test: PonyTest) =>
    test(_TestSessionDataApply)
    test(_TestSessionDataApplyMissing)
    test(_TestSessionDataGetOr)
    test(_TestSessionDataContains)
    test(_TestSessionDataSize)
    test(_TestSessionDataIsNew)
    test(_TestSessionDataEmpty)
    test(_TestSessionDataId)
    test(Property1UnitTest[USize](_PropSessionDataPairs))

class \nodoc\ iso _TestSessionDataApply is UnitTest
  fun name(): String => "SessionData/apply"

  fun apply(h: TestHelper) ? =>
    let data = _TestSessionDataHelper.with_pairs([
      ("user", "alice"); ("role", "admin")])
    h.assert_eq[String]("alice", data("user")?)
    h.assert_eq[String]("admin", data("role")?)

class \nodoc\ iso _TestSessionDataApplyMissing is UnitTest
  fun name(): String => "SessionData/apply-missing"

  fun apply(h: TestHelper) =>
    let data = _TestSessionDataHelper.with_pairs([("user", "alice")])
    try
      data("absent")?
      h.fail("expected error for missing key")
    end

class \nodoc\ iso _TestSessionDataGetOr is UnitTest
  fun name(): String => "SessionData/get_or"

  fun apply(h: TestHelper) =>
    let data = _TestSessionDataHelper.with_pairs([("user", "alice")])
    h.assert_eq[String]("alice", data.get_or("user", "default"))
    h.assert_eq[String]("default", data.get_or("absent", "default"))

class \nodoc\ iso _TestSessionDataContains is UnitTest
  fun name(): String => "SessionData/contains"

  fun apply(h: TestHelper) =>
    let data = _TestSessionDataHelper.with_pairs([("user", "alice")])
    h.assert_true(data.contains("user"))
    h.assert_false(data.contains("absent"))

class \nodoc\ iso _TestSessionDataSize is UnitTest
  fun name(): String => "SessionData/size"

  fun apply(h: TestHelper) =>
    let empty = SessionData._empty("id1")
    h.assert_eq[USize](0, empty.size())
    let data = _TestSessionDataHelper.with_pairs([
      ("a", "1"); ("b", "2"); ("c", "3")])
    h.assert_eq[USize](3, data.size())

class \nodoc\ iso _TestSessionDataIsNew is UnitTest
  fun name(): String => "SessionData/is_new"

  fun apply(h: TestHelper) =>
    let new_session = SessionData._create("id1",
      recover val Map[String, String] end where is_new' = true)
    h.assert_true(new_session.is_new())
    let loaded = SessionData._create("id2",
      recover val Map[String, String] end where is_new' = false)
    h.assert_false(loaded.is_new())

class \nodoc\ iso _TestSessionDataEmpty is UnitTest
  fun name(): String => "SessionData/empty"

  fun apply(h: TestHelper) =>
    let data = SessionData._empty("session-123")
    h.assert_true(data.is_new())
    h.assert_eq[USize](0, data.size())
    h.assert_eq[String]("session-123", data.id())

class \nodoc\ iso _TestSessionDataId is UnitTest
  fun name(): String => "SessionData/id"

  fun apply(h: TestHelper) =>
    let data = _TestSessionDataHelper.with_id("my-session-id")
    h.assert_eq[String]("my-session-id", data.id())

class \nodoc\ iso _PropSessionDataPairs is Property1[USize]
  """
  Build SessionData from generated key-value pairs. Verify pairs() yields
  all entries and count matches size().
  """

  fun name(): String => "SessionData/prop-pairs"

  fun gen(): Generator[USize] =>
    Generators.usize(0, 20)

  fun property(sample: USize, h: PropertyHelper) =>
    // Build map with sample number of entries
    let count = sample
    let expected = Map[String, String]
    let m: Map[String, String] iso = recover iso Map[String, String] end
    var i: USize = 0
    while i < count do
      let k: String val = "key" + i.string()
      let v: String val = "val" + i.string()
      m(k) = v
      expected(k) = v
      i = i + 1
    end
    let data = SessionData._create("id", consume m)
    h.assert_eq[USize](count, data.size())

    // Verify all pairs are present
    var pair_count: USize = 0
    for (k, v) in data.pairs() do
      try
        h.assert_eq[String](expected(k)?, v)
      else
        h.fail("unexpected key: " + k)
        return
      end
      pair_count = pair_count + 1
    end
    h.assert_eq[USize](count, pair_count)

// --- Test helpers ---

primitive \nodoc\ _TestSessionDataHelper
  fun with_pairs(
    pairs: Array[(String val, String val)] val)
    : SessionData val
  =>
    let m: Map[String, String] iso = recover iso Map[String, String] end
    for (k, v) in pairs.values() do
      m(k) = v
    end
    SessionData._create("test-id", consume m)

  fun with_id(id: String val): SessionData val =>
    SessionData._create(id, recover val Map[String, String] end)
