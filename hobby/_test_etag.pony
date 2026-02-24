use "pony_test"
use "pony_check"

primitive \nodoc\ _TestETagList
  fun tests(test: PonyTest) =>
    test(_TestETagFormat)
    test(_TestETagDeterministic)
    test(_TestETagExactMatch)
    test(_TestETagWildcard)
    test(_TestETagNoMatch)
    test(_TestETagCommaSeparatedMatch)
    test(_TestETagCommaSeparatedNoMatch)
    test(_TestETagStrongMatchesWeak)
    test(_TestETagCaseInsensitivePrefix)
    test(Property1UnitTest[U64](_PropertyETagSelfMatch))
    test(Property1UnitTest[U64](_PropertyETagWildcardMatch))

// --- Example-based tests ---

class \nodoc\ iso _TestETagFormat is UnitTest
  """ETag has expected W/"inode-size-mtime" format."""
  fun name(): String => "etag/format"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("W/\"1-2048-12345\"", _ETag(1, 2048, 12345))

class \nodoc\ iso _TestETagDeterministic is UnitTest
  """Same inputs produce the same ETag."""
  fun name(): String => "etag/deterministic"

  fun apply(h: TestHelper) =>
    h.assert_eq[String](_ETag(42, 1024, 99999), _ETag(42, 1024, 99999))

class \nodoc\ iso _TestETagExactMatch is UnitTest
  """Exact weak ETag match."""
  fun name(): String => "etag/matches/exact"

  fun apply(h: TestHelper) =>
    let etag = _ETag(1, 20, 12345)
    h.assert_true(_ETag.matches(etag, etag))

class \nodoc\ iso _TestETagWildcard is UnitTest
  """`*` matches any ETag."""
  fun name(): String => "etag/matches/wildcard"

  fun apply(h: TestHelper) =>
    h.assert_true(_ETag.matches("*", _ETag(1, 20, 12345)))

class \nodoc\ iso _TestETagNoMatch is UnitTest
  """Non-matching ETag."""
  fun name(): String => "etag/matches/no match"

  fun apply(h: TestHelper) =>
    h.assert_false(_ETag.matches("W/\"9-9-9\"", _ETag(1, 20, 12345)))

class \nodoc\ iso _TestETagCommaSeparatedMatch is UnitTest
  """Comma-separated list with a match."""
  fun name(): String => "etag/matches/comma separated match"

  fun apply(h: TestHelper) =>
    let etag = _ETag(1, 20, 12345)
    h.assert_true(_ETag.matches("W/\"a-b-c\", " + etag, etag))

class \nodoc\ iso _TestETagCommaSeparatedNoMatch is UnitTest
  """Comma-separated list with no match."""
  fun name(): String => "etag/matches/comma separated no match"

  fun apply(h: TestHelper) =>
    h.assert_false(
      _ETag.matches("W/\"a-b-c\", W/\"x-y-z\"", _ETag(1, 20, 12345)))

class \nodoc\ iso _TestETagStrongMatchesWeak is UnitTest
  """Strong ETag (no W/ prefix) matches weak via weak comparison."""
  fun name(): String => "etag/matches/strong matches weak"

  fun apply(h: TestHelper) =>
    let etag = _ETag(1, 20, 12345)
    // Strong form: strip W/ from the generated etag to get "1-20-12345"
    // and wrap in quotes
    h.assert_true(_ETag.matches("\"1-20-12345\"", etag))

class \nodoc\ iso _TestETagCaseInsensitivePrefix is UnitTest
  """Lowercase `w/` prefix is treated the same as `W/`."""
  fun name(): String => "etag/matches/case insensitive prefix"

  fun apply(h: TestHelper) =>
    let etag = _ETag(1, 20, 12345)
    h.assert_true(_ETag.matches("w/\"1-20-12345\"", etag))

// --- Property tests ---

class \nodoc\ iso _PropertyETagSelfMatch is Property1[U64]
  """An ETag always matches itself."""
  fun name(): String => "etag/property/self match"

  fun gen(): Generator[U64] => Generators.u64()

  fun property(inode: U64, h: PropertyHelper) =>
    let etag = _ETag(inode, 1024, 12345)
    h.assert_true(_ETag.matches(etag, etag))

class \nodoc\ iso _PropertyETagWildcardMatch is Property1[U64]
  """`*` matches any generated ETag."""
  fun name(): String => "etag/property/wildcard match"

  fun gen(): Generator[U64] => Generators.u64()

  fun property(inode: U64, h: PropertyHelper) =>
    h.assert_true(_ETag.matches("*", _ETag(inode, 512, 99999)))
