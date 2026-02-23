use "pony_test"
use "pony_check"

primitive _TestContentTypeList
  fun tests(test: PonyTest) =>
    test(Property1UnitTest[String](_PropertyKnownExtensionMapsToMime))
    test(Property1UnitTest[String](_PropertyUnknownExtensionMapsToOctetStream))
    test(_TestContentTypeCaseInsensitive)

// --- Generators ---

primitive _GenKnownExtension
  """Generate a known file extension."""
  fun apply(): Generator[String] =>
    Generators.one_of[String]([
      "html"; "htm"; "css"; "js"; "json"; "xml"; "txt"
      "png"; "jpg"; "jpeg"; "gif"; "svg"; "ico"
      "woff"; "woff2"; "pdf"; "wasm"
    ])

primitive _GenUnknownExtension
  """Generate an extension guaranteed not to be in the known set."""
  fun apply(): Generator[String] =>
    // Use a prefix that can't collide with any known extension
    Generators.ascii(1, 5 where range = ASCIILetters)
      .map[String]({(s: String): String => "zz" + s})

// --- Property tests ---

class \nodoc\ iso _PropertyKnownExtensionMapsToMime is Property1[String]
  """Every known extension maps to a non-empty, non-default MIME type."""
  fun name(): String => "content-type/property/known extension maps to MIME"

  fun gen(): Generator[String] => _GenKnownExtension()

  fun property(ext: String, h: PropertyHelper) =>
    let mime = _ContentType(ext)
    h.assert_ne[String]("", mime)
    h.assert_ne[String]("application/octet-stream", mime)

class \nodoc\ iso _PropertyUnknownExtensionMapsToOctetStream is
  Property1[String]
  """Unknown extensions map to application/octet-stream."""
  fun name(): String =>
    "content-type/property/unknown extension maps to octet-stream"

  fun gen(): Generator[String] => _GenUnknownExtension()

  fun property(ext: String, h: PropertyHelper) =>
    h.assert_eq[String]("application/octet-stream", _ContentType(ext))

// --- Example-based tests ---

class \nodoc\ iso _TestContentTypeCaseInsensitive is UnitTest
  """Content-type lookup is case-insensitive."""
  fun name(): String => "content-type/case insensitive"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("text/html", _ContentType("HTML"))
    h.assert_eq[String]("text/css", _ContentType("CSS"))
    h.assert_eq[String]("image/png", _ContentType("PNG"))
    h.assert_eq[String]("text/javascript", _ContentType("Js"))
