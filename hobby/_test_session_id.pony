use "collections"
use "pony_test"
use "pony_check"

primitive \nodoc\ _TestSessionIdList
  fun tests(test: PonyTest) =>
    test(_TestSessionIdLength)
    test(_TestSessionIdHexChars)
    test(Property1UnitTest[USize](_PropSessionIdLength))
    test(Property1UnitTest[USize](_PropSessionIdHexChars))
    test(Property1UnitTest[USize](_PropSessionIdUnique))

class \nodoc\ iso _TestSessionIdLength is UnitTest
  fun name(): String => "SessionId/length"

  fun apply(h: TestHelper) =>
    let id =
      try SessionId.generate()?
      else h.fail("generate failed"); return
      end
    h.assert_eq[USize](64, id.size())

class \nodoc\ iso _TestSessionIdHexChars is UnitTest
  fun name(): String => "SessionId/hex-chars"

  fun apply(h: TestHelper) =>
    let id =
      try SessionId.generate()?
      else h.fail("generate failed"); return
      end
    for c in id.values() do
      let valid =
        ((c >= '0') and (c <= '9')) or ((c >= 'a') and (c <= 'f'))
      if not valid then
        h.fail("non-hex character: " + String.from_utf32(c.u32()))
        return
      end
    end

class \nodoc\ iso _PropSessionIdLength is Property1[USize]
  """Every generated session ID is exactly 64 characters."""

  fun name(): String => "SessionId/prop-length"

  fun gen(): Generator[USize] =>
    Generators.usize(0, 100)

  fun property(sample: USize, h: PropertyHelper) =>
    let id =
      try SessionId.generate()?
      else h.fail("generate failed"); return
      end
    h.assert_eq[USize](64, id.size())

class \nodoc\ iso _PropSessionIdHexChars is Property1[USize]
  """Every character in a generated session ID is in [0-9a-f]."""

  fun name(): String => "SessionId/prop-hex-chars"

  fun gen(): Generator[USize] =>
    Generators.usize(0, 100)

  fun property(sample: USize, h: PropertyHelper) =>
    let id =
      try SessionId.generate()?
      else h.fail("generate failed"); return
      end
    for c in id.values() do
      let valid =
        ((c >= '0') and (c <= '9')) or ((c >= 'a') and (c <= 'f'))
      if not valid then
        h.fail("non-hex character: " + String.from_utf32(c.u32()))
        return
      end
    end

class \nodoc\ iso _PropSessionIdUnique is Property1[USize]
  """50 generated IDs per sample are all distinct."""

  fun name(): String => "SessionId/prop-unique"

  fun gen(): Generator[USize] =>
    Generators.usize(0, 100)

  fun property(sample: USize, h: PropertyHelper) =>
    let ids = Set[String]
    var i: USize = 0
    while i < 50 do
      let id =
        try SessionId.generate()?
        else h.fail("generate failed"); return
        end
      ids.set(id)
      i = i + 1
    end
    h.assert_eq[USize](50, ids.size())
