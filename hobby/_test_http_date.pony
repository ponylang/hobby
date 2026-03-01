use "pony_test"
use "pony_check"

primitive \nodoc\ _TestHTTPDateList
  fun tests(test: PonyTest) =>
    test(_TestHTTPDateEpochZero)
    test(_TestHTTPDateSunday)
    test(_TestHTTPDateKnownDate)
    test(Property1UnitTest[I64](_PropertyHTTPDateLength))
    test(Property1UnitTest[I64](_PropertyHTTPDateEndsWithGMT))
    test(Property1UnitTest[I64](_PropertyHTTPDateStartsWithDayName))
    test(Property1UnitTest[I64](_PropertyHTTPDateDayPadded))

// --- Generators ---
primitive \nodoc\ _GenEpochSeconds
  """
  Generate non-negative epoch seconds for HTTP date testing.
  """
  fun apply(): Generator[I64] =>
    // Range from 0 to ~year 2100 (4102444800)
    Generators.i64(0, 4_102_444_800)

// --- Example-based tests ---
class \nodoc\ iso _TestHTTPDateEpochZero is UnitTest
  """
  Epoch 0 formats as Thu, 01 Jan 1970 00:00:00 GMT.
  """
  fun name(): String => "http-date/epoch zero"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("Thu, 01 Jan 1970 00:00:00 GMT", _HTTPDate(0))

class \nodoc\ iso _TestHTTPDateSunday is UnitTest
  """
  Known Sunday date guards against day_of_week indexing bugs.
  Jan 4, 1970 (epoch 259200) is a Sunday.
  """
  fun name(): String => "http-date/sunday"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("Sun, 04 Jan 1970 00:00:00 GMT", _HTTPDate(259200))

class \nodoc\ iso _TestHTTPDateKnownDate is UnitTest
  """
  Known date in a different month and year for coverage.
  """
  fun name(): String => "http-date/known date"

  fun apply(h: TestHelper) =>
    // 2024-07-15 14:30:00 UTC = 1721053800
    // July 15, 2024 is a Monday
    h.assert_eq[String](
      "Mon, 15 Jul 2024 14:30:00 GMT", _HTTPDate(1_721_053_800))

// --- Property tests ---
class \nodoc\ iso _PropertyHTTPDateLength is Property1[I64]
  """
  IMF-fixdate is always 29 characters.
  """
  fun name(): String => "http-date/property/length is 29"

  fun gen(): Generator[I64] => _GenEpochSeconds()

  fun property(seconds: I64, h: PropertyHelper) =>
    h.assert_eq[USize](29, _HTTPDate(seconds).size())

class \nodoc\ iso _PropertyHTTPDateEndsWithGMT is Property1[I64]
  """
  Output always ends with ' GMT'.
  """
  fun name(): String => "http-date/property/ends with GMT"

  fun gen(): Generator[I64] => _GenEpochSeconds()

  fun property(seconds: I64, h: PropertyHelper) =>
    let result = _HTTPDate(seconds)
    h.assert_true(
      result.contains(" GMT"),
      "Expected ' GMT' suffix in: " + result)

class \nodoc\ iso _PropertyHTTPDateStartsWithDayName is Property1[I64]
  """
  Output always starts with a valid 3-letter day name followed by ', '.
  """
  fun name(): String => "http-date/property/starts with day name"

  fun gen(): Generator[I64] => _GenEpochSeconds()

  fun property(seconds: I64, h: PropertyHelper) =>
    let result = _HTTPDate(seconds)
    let valid_prefixes =
      [ "Sun, "; "Mon, "; "Tue, "; "Wed, "
        "Thu, "; "Fri, "; "Sat, " ]
    var found = false
    for prefix in valid_prefixes.values() do
      if result.substring(0, 5) == prefix then
        found = true
        break
      end
    end
    h.assert_true(
      found,
      "Expected valid day prefix in: " + result)

class \nodoc\ iso _PropertyHTTPDateDayPadded is Property1[I64]
  """
  Day-of-month is always 2 digits (zero-padded).
  """
  fun name(): String => "http-date/property/day is 2 digits"

  fun gen(): Generator[I64] => _GenEpochSeconds()

  fun property(seconds: I64, h: PropertyHelper) =>
    let result = _HTTPDate(seconds)
    // Day-of-month occupies positions 5-6 in "Thu, 01 Jan 1970..."
    try
      let d1 = result(5)?
      let d2 = result(6)?
      h.assert_true(
        (d1 >= '0') and (d1 <= '9'),
        "Day digit 1 not numeric in: " + result)
      h.assert_true(
        (d2 >= '0') and (d2 <= '9'),
        "Day digit 2 not numeric in: " + result)
    else
      h.fail("Could not access day digits in: " + result)
    end
