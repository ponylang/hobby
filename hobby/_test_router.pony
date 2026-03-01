use "pony_test"
use "pony_check"
use "collections"
use stallion = "stallion"

primitive \nodoc\ _TestRouterList
  fun tests(test: PonyTest) =>
    test(Property1UnitTest[String](_PropertyStaticRouteMatches))
    test(Property1UnitTest[String](_PropertyUnregisteredReturnsNone))
    test(
      Property1UnitTest[(String, String)](
        _PropertyParamExtraction))
    test(
      Property1UnitTest[(String, String, String)](
        _PropertyMultipleParams))
    test(Property1UnitTest[stallion.Method](_PropertyMethodIsolation))
    test(Property1UnitTest[String](_PropertyWildcardCapture))
    test(_TestStaticPriorityOverParam)
    test(_TestRootPath)
    test(_TestOverlappingPrefixes)
    test(_TestWildcardSingleSegment)
    test(_TestTrailingSlashNormalization)

// --- Generators ---
primitive \nodoc\ _GenPathSegment
  """
  Generate a single path segment: lowercase letters, length 1-10.
  """
  fun apply(): Generator[String] =>
    Generators.ascii(1, 10 where range = ASCIILetters)

primitive \nodoc\ _GenStaticPath
  """
  Generate a static path like `/foo/bar/baz` with 1-3 segments.
  """
  fun apply(): Generator[String] =>
    Generators.map2[String, String, String](
      _GenPathSegment(),
      _GenPathSegment(),
      {(a: String, b: String): String =>
        recover val
          String
            .> append("/")
            .> append(a)
            .> append("/")
            .> append(b)
        end
      })

primitive \nodoc\ _GenParamName
  """
  Generate a parameter name: alphabetic, length 1-10.
  """
  fun apply(): Generator[String] =>
    Generators.ascii(1, 10 where range = ASCIILetters)

primitive \nodoc\ _GenMethod
  """
  Generate a random HTTP method.
  """
  fun apply(): Generator[stallion.Method] =>
    Generators.one_of[stallion.Method](
      [ stallion.GET; stallion.POST
        stallion.PUT; stallion.DELETE
        stallion.PATCH; stallion.HEAD
        stallion.OPTIONS ])

// --- Test handler ---
primitive \nodoc\ _NoOpHandler is Handler
  fun apply(ctx: Context ref) => ctx.respond(stallion.StatusOK, "ok")

// --- Property tests ---
class \nodoc\ iso _PropertyStaticRouteMatches is Property1[String]
  """
  A registered static route always matches.
  """
  fun name(): String => "router/property/static route matches"

  fun gen(): Generator[String] => _GenStaticPath()

  fun property(path: String, h: PropertyHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, path, _NoOpHandler, None)
    let router = builder.build()
    match router.lookup(stallion.GET, path)
    | let m: _RouteMatch =>
      h.assert_eq[USize](0, m.params.size())
    else
      h.fail("expected match for " + path)
    end

class \nodoc\ iso _PropertyUnregisteredReturnsNone is Property1[String]
  """
  An unregistered path returns None.
  """
  fun name(): String => "router/property/unregistered returns None"

  fun gen(): Generator[String] => _GenStaticPath()

  fun property(path: String, h: PropertyHelper) =>
    let router = _RouterBuilder.build()
    match router.lookup(stallion.GET, path)
    | let _: _RouteMatch =>
      h.fail("expected None for " + path + " on empty router")
    end

class \nodoc\ iso _PropertyParamExtraction is
  Property1[(String, String)]
  """
  `:name` segments are captured correctly.
  """
  fun name(): String => "router/property/param extraction"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](
      _GenStaticPath(),
      _GenParamName())

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let prefix, let param_name) = sample
    let pattern: String val = prefix + "/:" + param_name
    let builder = _RouterBuilder
    builder.add(stallion.GET, pattern, _NoOpHandler, None)
    let router = builder.build()

    let lookup_path: String val = prefix + "/testvalue"
    match router.lookup(stallion.GET, lookup_path)
    | let m: _RouteMatch =>
      try
        h.assert_eq[String]("testvalue", m.params(param_name)?)
      else
        h.fail("param not found in match")
      end
    else
      h.fail("expected match")
    end

class \nodoc\ iso _PropertyMultipleParams is
  Property1[(String, String, String)]
  """
  Multiple `:name` segments are all extracted.
  """
  fun name(): String => "router/property/multiple params"

  fun gen(): Generator[(String, String, String)] =>
    Generators.zip3[String, String, String](
      _GenPathSegment(),
      _GenParamName(),
      _GenParamName())

  fun property(sample: (String, String, String), h: PropertyHelper) =>
    (let seg, let p1, let p2) = sample
    // Ensure distinct param names
    let param2: String val = if p1 == p2 then p2 + "2" else p2 end
    let pattern: String val = "/" + seg + "/:" + p1 + "/:" + param2
    let builder = _RouterBuilder
    builder.add(stallion.GET, pattern, _NoOpHandler, None)
    let router = builder.build()

    let lookup_path: String val = "/" + seg + "/val1/val2"
    match router.lookup(stallion.GET, lookup_path)
    | let m: _RouteMatch =>
      try
        h.assert_eq[String]("val1", m.params(p1)?)
      else
        h.fail("param p1 not found")
      end
      try
        h.assert_eq[String]("val2", m.params(param2)?)
      else
        h.fail("param p2 not found")
      end
    else
      h.fail("expected match")
    end

class \nodoc\ iso _PropertyMethodIsolation is
  Property1[stallion.Method]
  """
  A route registered for one method does not match another.
  """
  fun name(): String => "router/property/method isolation"

  fun gen(): Generator[stallion.Method] => _GenMethod()

  fun property(method: stallion.Method, h: PropertyHelper) =>
    let builder = _RouterBuilder
    builder.add(method, "/test", _NoOpHandler, None)
    let router = builder.build()

    // Should match the registered method
    match router.lookup(method, "/test")
    | let _: _RouteMatch => None
    else
      h.fail("expected match for registered method")
    end

    // Should NOT match a different method
    let other: stallion.Method =
      if method is stallion.GET then
        stallion.POST
      else
        stallion.GET
      end
    match router.lookup(other, "/test")
    | let _: _RouteMatch =>
      h.fail("should not match different method")
    end

class \nodoc\ iso _PropertyWildcardCapture is Property1[String]
  """
  `*name` captures the remainder of the path.
  """
  fun name(): String => "router/property/wildcard capture"

  fun gen(): Generator[String] => _GenPathSegment()

  fun property(seg: String, h: PropertyHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/files/*path", _NoOpHandler, None)
    let router = builder.build()

    let lookup_path: String val = "/files/" + seg + "/extra"
    match router.lookup(stallion.GET, lookup_path)
    | let m: _RouteMatch =>
      try
        let expected: String val = seg + "/extra"
        h.assert_eq[String](expected, m.params("path")?)
      else
        h.fail("wildcard param 'path' not found")
      end
    else
      h.fail("expected match")
    end

// --- Example-based tests ---
class \nodoc\ iso _TestStaticPriorityOverParam is UnitTest
  """
  `/users/new` matches static before `/users/:id`.
  """
  fun name(): String => "router/static priority over param"

  fun apply(h: TestHelper) =>
    let static_handler = _TestMarkerHandler("static")
    let param_handler = _TestMarkerHandler("param")
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/users/:id", param_handler, None)
    builder.add(stallion.GET, "/users/new", static_handler, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/users/new")
    | let m: _RouteMatch =>
      h.assert_is[Handler](static_handler, m.handler)
    else
      h.fail("expected match for /users/new")
    end

    match router.lookup(stallion.GET, "/users/42")
    | let m: _RouteMatch =>
      h.assert_is[Handler](param_handler, m.handler)
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /users/42")
    end

class \nodoc\ val _TestMarkerHandler is Handler
  let _label: String

  new val create(label: String) => _label = label

  fun apply(ctx: Context ref) => ctx.respond(stallion.StatusOK, _label)

class \nodoc\ iso _TestRootPath is UnitTest
  """
  Root path `/` matches.
  """
  fun name(): String => "router/root path"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/", _NoOpHandler, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/")
    | let _: _RouteMatch => None
    else
      h.fail("expected match for /")
    end

class \nodoc\ iso _TestOverlappingPrefixes is UnitTest
  """
  Multiple routes with overlapping prefixes dispatch correctly.
  """
  fun name(): String => "router/overlapping prefixes"

  fun apply(h: TestHelper) =>
    let h1 = _TestMarkerHandler("v1")
    let h2 = _TestMarkerHandler("v2")
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/api/v1/users", h1, None)
    builder.add(stallion.GET, "/api/v2/users", h2, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/api/v1/users")
    | let m: _RouteMatch => h.assert_is[Handler](h1, m.handler)
    else
      h.fail("expected match for /api/v1/users")
    end

    match router.lookup(stallion.GET, "/api/v2/users")
    | let m: _RouteMatch => h.assert_is[Handler](h2, m.handler)
    else
      h.fail("expected match for /api/v2/users")
    end

class \nodoc\ iso _TestWildcardSingleSegment is UnitTest
  """
  Wildcard captures a single segment.
  """
  fun name(): String => "router/wildcard single segment"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/files/*path", _NoOpHandler, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/files/readme.txt")
    | let m: _RouteMatch =>
      try
        h.assert_eq[String]("readme.txt", m.params("path")?)
      else
        h.fail("wildcard param 'path' not found")
      end
    else
      h.fail("expected match for /files/readme.txt")
    end

    // /files/ normalizes to /files which has no remainder for the wildcard
    match router.lookup(stallion.GET, "/files/")
    | let _: _RouteMatch =>
      h.fail(
        "should not match /files/ " +
        "(normalizes to /files, no wildcard content)")
    end

class \nodoc\ iso _TestTrailingSlashNormalization is UnitTest
  """
  `/users/` and `/users` match the same route.
  """
  fun name(): String => "router/trailing slash normalization"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/users", _NoOpHandler, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/users")
    | let _: _RouteMatch => None
    else
      h.fail("expected match for /users")
    end

    match router.lookup(stallion.GET, "/users/")
    | let _: _RouteMatch => None
    else
      h.fail("expected match for /users/ (trailing slash)")
    end
