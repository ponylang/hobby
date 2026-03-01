use "pony_test"
use "pony_check"

primitive \nodoc\ _TestContentTypeList
  fun tests(test: PonyTest) =>
    test(Property1UnitTest[String](_PropertyKnownExtensionMapsToMIME))
    test(Property1UnitTest[String](_PropertyUnknownExtensionMapsToOctetStream))
    test(_TestContentTypeCaseInsensitive)
    test(Property1UnitTest[(String, String)](_PropertyOverrideReplacesDefault))
    test(Property1UnitTest[(String, String)](_PropertyOverrideAddsNew))
    test(_TestOverridePreservesDefaults)
    test(_TestOverrideCaseInsensitive)

// --- Generators ---
primitive \nodoc\ _GenKnownExtension
  """
  Generate a known file extension.
  """
  fun apply(): Generator[String] =>
    Generators.one_of[String](
      [ "html"; "htm"; "css"; "js"
        "json"; "xml"; "txt"
        "png"; "jpg"; "jpeg"; "gif"
        "svg"; "ico"
        "woff"; "woff2"; "pdf"; "wasm" ])

primitive \nodoc\ _GenUnknownExtension
  """
  Generate an extension guaranteed not to be in the known set.
  """
  fun apply(): Generator[String] =>
    // Use a prefix that can't collide with any known extension
    Generators.ascii(1, 5 where range = ASCIILetters)
      .map[String]({(s: String): String => "zz" + s })

primitive \nodoc\ _GenMIMEType
  """
  Generate a random MIME-like string.
  """
  fun apply(): Generator[String] =>
    Generators.ascii(3, 20 where range = ASCIILetters)
      .map[String]({(s: String): String => "test/" + s })

// --- Property tests ---
class \nodoc\ iso _PropertyKnownExtensionMapsToMIME is Property1[String]
  """
  Every known extension maps to a non-empty, non-default MIME type.
  """
  fun name(): String => "content-type/property/known extension maps to MIME"

  fun gen(): Generator[String] => _GenKnownExtension()

  fun property(ext: String, h: PropertyHelper) =>
    let ct = ContentTypes
    let mime = ct(ext)
    h.assert_ne[String]("", mime)
    h.assert_ne[String]("application/octet-stream", mime)

class \nodoc\ iso _PropertyUnknownExtensionMapsToOctetStream is
  Property1[String]
  """
  Unknown extensions map to application/octet-stream.
  """
  fun name(): String =>
    "content-type/property/unknown extension maps to octet-stream"

  fun gen(): Generator[String] => _GenUnknownExtension()

  fun property(ext: String, h: PropertyHelper) =>
    let ct = ContentTypes
    h.assert_eq[String]("application/octet-stream", ct(ext))

class \nodoc\ iso _PropertyOverrideReplacesDefault is
  Property1[(String, String)]
  """
  Overriding a known extension replaces the default MIME type.
  """
  fun name(): String =>
    "content-type/property/override replaces default"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](_GenKnownExtension(), _GenMIMEType())

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let ext, let mime) = sample
    let ct = ContentTypes.add(ext, mime)
    h.assert_eq[String](mime, ct(ext))

class \nodoc\ iso _PropertyOverrideAddsNew is
  Property1[(String, String)]
  """
  Adding an unknown extension via add makes it resolvable.
  """
  fun name(): String =>
    "content-type/property/override adds new"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](_GenUnknownExtension(), _GenMIMEType())

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let ext, let mime) = sample
    let ct = ContentTypes.add(ext, mime)
    h.assert_eq[String](mime, ct(ext))

// --- Example-based tests ---
class \nodoc\ iso _TestContentTypeCaseInsensitive is UnitTest
  """
  Content-type lookup is case-insensitive.
  """
  fun name(): String => "content-type/case insensitive"

  fun apply(h: TestHelper) =>
    let ct = ContentTypes
    h.assert_eq[String]("text/html", ct("HTML"))
    h.assert_eq[String]("text/css", ct("CSS"))
    h.assert_eq[String]("image/png", ct("PNG"))
    h.assert_eq[String]("text/javascript", ct("Js"))

class \nodoc\ iso _TestOverridePreservesDefaults is UnitTest
  """
  Overriding one extension doesn't affect other defaults.
  """
  fun name(): String => "content-type/override preserves defaults"

  fun apply(h: TestHelper) =>
    let ct = ContentTypes.add("custom", "application/x-custom")
    h.assert_eq[String]("text/html", ct("html"))
    h.assert_eq[String]("text/css", ct("css"))
    h.assert_eq[String]("image/png", ct("png"))
    h.assert_eq[String]("application/json", ct("json"))

class \nodoc\ iso _TestOverrideCaseInsensitive is UnitTest
  """
  Override keys are case-insensitive.
  """
  fun name(): String => "content-type/override case insensitive"

  fun apply(h: TestHelper) =>
    let ct = ContentTypes.add("WEBP", "image/webp")
    h.assert_eq[String]("image/webp", ct("webp"))
    h.assert_eq[String]("image/webp", ct("WEBP"))
    h.assert_eq[String]("image/webp", ct("Webp"))
