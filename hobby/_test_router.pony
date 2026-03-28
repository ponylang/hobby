use "pony_test"
use "pony_check"
use "collections"
use stallion = "stallion"

primitive \nodoc\ _TestRouterList
  fun tests(test: PonyTest) =>
    test(Property1UnitTest[String](_PropertyStaticRouteMatches))
    test(Property1UnitTest[String](_PropertyUnregisteredReturnsNone))
    test(Property1UnitTest[
      (String, String)](_PropertyParamExtraction))
    test(Property1UnitTest[
      (String, String, String)](_PropertyMultipleParams))
    test(Property1UnitTest[stallion.Method](_PropertyMethodIsolation))
    test(Property1UnitTest[String](_PropertyWildcardCapture))
    test(_TestStaticPriorityOverParam)
    test(_TestRootPath)
    test(_TestOverlappingPrefixes)
    test(_TestWildcardSingleSegment)
    test(_TestTrailingSlashNormalization)
    test(_TestSplitThenParam)
    test(_TestSplitThenWildcard)
    test(_TestSplitThenMultipleParams)
    test(_TestSplitParamThenStatic)
    test(_TestSplitAtSegmentBoundary)
    test(_TestSplitMidSegmentParam)
    test(_TestDeepNestedParamSharedPrefix)
    test(Property1UnitTest[
      (Array[USize] val, Array[USize] val)](
      _PropertyInsertionOrderInvariance))

// --- Generators ---

primitive \nodoc\ _GenPathSegment
  """Generate a single path segment: letters or digits, length 1-10."""
  fun apply(): Generator[String] =>
    Generators.ascii(1, 10 where range = ASCIILetters)
      .union[String](Generators.ascii(1, 5 where range = ASCIIDigits))

primitive \nodoc\ _GenStaticPath
  """Generate a static path with 1 or 2 segments."""
  fun apply(): Generator[String] =>
    Generators.map2[String, String, String](
      _GenPathSegment(),
      _GenPathSegment(),
      {(a: String, b: String): String =>
        recover val
          let s = String
          s.append("/")
          s.append(a)
          s.append("/")
          s.append(b)
          s
        end
      }).union[String](
    _GenPathSegment().map[String]({(a: String): String => "/" + a}))

primitive \nodoc\ _GenParamName
  """Generate a parameter name: alphabetic, length 1-10."""
  fun apply(): Generator[String] =>
    Generators.ascii(1, 10 where range = ASCIILetters)

primitive \nodoc\ _GenMethod
  """Generate a random HTTP method."""
  fun apply(): Generator[stallion.Method] =>
    Generators.one_of[stallion.Method]([
      stallion.GET; stallion.POST; stallion.PUT; stallion.DELETE
      stallion.PATCH; stallion.HEAD; stallion.OPTIONS
    ])

// --- Test factory ---

primitive \nodoc\ _NoOpFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    RequestHandler(consume ctx).respond(stallion.StatusOK, "ok")

// --- Property tests ---

class \nodoc\ iso _PropertyStaticRouteMatches is Property1[String]
  """A registered static route always matches."""
  fun name(): String => "router/property/static route matches"

  fun gen(): Generator[String] => _GenStaticPath()

  fun property(path: String, h: PropertyHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, path, _NoOpFactory, None)
    let router = builder.build()
    match router.lookup(stallion.GET, path)
    | let m: _RouteMatch =>
      h.assert_eq[USize](0, m.params.size())
    else
      h.fail("expected match for " + path)
    end

class \nodoc\ iso _PropertyUnregisteredReturnsNone is Property1[String]
  """An unregistered path returns None."""
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
  """`:name` segments are captured correctly."""
  fun name(): String => "router/property/param extraction"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](
      _GenStaticPath(),
      _GenParamName())

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let prefix, let param_name) = sample
    let pattern: String val = prefix + "/:" + param_name
    let builder = _RouterBuilder
    builder.add(stallion.GET, pattern, _NoOpFactory, None)
    let router = builder.build()

    let lookup_path: String val = prefix + "/testvalue"
    match \exhaustive\ router.lookup(stallion.GET, lookup_path)
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
  """Multiple `:name` segments are all extracted."""
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
    builder.add(stallion.GET, pattern, _NoOpFactory, None)
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
  """A route registered for one method does not match another."""
  fun name(): String => "router/property/method isolation"

  fun gen(): Generator[stallion.Method] => _GenMethod()

  fun property(method: stallion.Method, h: PropertyHelper) =>
    let builder = _RouterBuilder
    builder.add(method, "/test", _NoOpFactory, None)
    let router = builder.build()

    // Should match the registered method
    match router.lookup(method, "/test")
    | let _: _RouteMatch => None
    else
      h.fail("expected match for registered method")
    end

    // Should NOT match a different method
    let other: stallion.Method = if method is stallion.GET then
      stallion.POST
    else
      stallion.GET
    end
    match router.lookup(other, "/test")
    | let _: _RouteMatch =>
      h.fail("should not match different method")
    end

class \nodoc\ iso _PropertyWildcardCapture is Property1[String]
  """`*name` captures the remainder of the path."""
  fun name(): String => "router/property/wildcard capture"

  fun gen(): Generator[String] => _GenPathSegment()

  fun property(seg: String, h: PropertyHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/files/*path", _NoOpFactory, None)
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
  """`/users/new` matches static before `/users/:id`."""
  fun name(): String => "router/static priority over param"

  fun apply(h: TestHelper) =>
    let static_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "static")
    } val
    let param_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "param")
    } val
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/users/:id", param_factory, None)
    builder.add(stallion.GET, "/users/new", static_factory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/users/new")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](static_factory, m.factory)
    else
      h.fail("expected match for /users/new")
    end

    match router.lookup(stallion.GET, "/users/42")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](param_factory, m.factory)
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /users/42")
    end

class \nodoc\ iso _TestRootPath is UnitTest
  """Root path `/` matches."""
  fun name(): String => "router/root path"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/", _NoOpFactory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/")
    | let _: _RouteMatch => None
    else
      h.fail("expected match for /")
    end

class \nodoc\ iso _TestOverlappingPrefixes is UnitTest
  """Multiple routes with overlapping prefixes dispatch correctly."""
  fun name(): String => "router/overlapping prefixes"

  fun apply(h: TestHelper) =>
    let f1: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "v1")
    } val
    let f2: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "v2")
    } val
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/api/v1/users", f1, None)
    builder.add(stallion.GET, "/api/v2/users", f2, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/api/v1/users")
    | let m: _RouteMatch => h.assert_is[HandlerFactory](f1, m.factory)
    else
      h.fail("expected match for /api/v1/users")
    end

    match router.lookup(stallion.GET, "/api/v2/users")
    | let m: _RouteMatch => h.assert_is[HandlerFactory](f2, m.factory)
    else
      h.fail("expected match for /api/v2/users")
    end

class \nodoc\ iso _TestWildcardSingleSegment is UnitTest
  """Wildcard captures a single segment."""
  fun name(): String => "router/wildcard single segment"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/files/*path", _NoOpFactory, None)
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
      h.fail("should not match /files/ (normalizes to /files, no wildcard content)")
    end

class \nodoc\ iso _TestTrailingSlashNormalization is UnitTest
  """`/users/` and `/users` match the same route."""
  fun name(): String => "router/trailing slash normalization"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/users", _NoOpFactory, None)
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

class \nodoc\ iso _TestSplitThenParam is UnitTest
  """
  Param route added after a static route with shared prefix is parsed.

  Regression: _insert_static stored the remaining suffix as a literal prefix
  instead of routing through _insert, so `:id` was never parsed as a param.
  """
  fun name(): String => "router/split then param"

  fun apply(h: TestHelper) =>
    let login_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "login")
    } val
    let user_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "user")
    } val
    let builder = _RouterBuilder
    // Static route first — creates a single node with long prefix
    builder.add(stallion.POST, "/a/b/c/login", login_factory, None)
    // Param route second — triggers split; remaining suffix contains `:id`
    builder.add(stallion.POST, "/a/b/c/user/:id/filter", user_factory, None)
    let router = builder.build()

    // The static route still works
    match router.lookup(stallion.POST, "/a/b/c/login")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](login_factory, m.factory)
    else
      h.fail("expected match for /a/b/c/login")
    end

    // The param route works and extracts the parameter
    match router.lookup(stallion.POST, "/a/b/c/user/42/filter")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](user_factory, m.factory)
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /a/b/c/user/42/filter")
    end

class \nodoc\ iso _TestSplitThenWildcard is UnitTest
  """Wildcard route added after a static route with shared prefix is parsed."""
  fun name(): String => "router/split then wildcard"

  fun apply(h: TestHelper) =>
    let exact_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "exact")
    } val
    let catch_all_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "catch-all")
    } val
    let builder = _RouterBuilder
    // Static route first
    builder.add(stallion.GET, "/static/page", exact_factory, None)
    // Wildcard route second — triggers split; remaining suffix contains `*`
    builder.add(stallion.GET, "/static/*rest", catch_all_factory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/static/page")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](exact_factory, m.factory)
    else
      h.fail("expected match for /static/page")
    end

    match router.lookup(stallion.GET, "/static/other/deep/path")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](catch_all_factory, m.factory)
      try
        h.assert_eq[String]("other/deep/path", m.params("rest")?)
      else
        h.fail("wildcard param 'rest' not found")
      end
    else
      h.fail("expected match for /static/other/deep/path")
    end

class \nodoc\ iso _TestSplitThenMultipleParams is UnitTest
  """Multiple params in the suffix after a split are all parsed correctly."""
  fun name(): String => "router/split then multiple params"

  fun apply(h: TestHelper) =>
    let static_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "static")
    } val
    let param_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "params")
    } val
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/api/v1/health", static_factory, None)
    builder.add(stallion.GET, "/api/v1/:resource/:id", param_factory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/api/v1/health")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](static_factory, m.factory)
    else
      h.fail("expected match for /api/v1/health")
    end

    match router.lookup(stallion.GET, "/api/v1/users/99")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](param_factory, m.factory)
      try
        h.assert_eq[String]("users", m.params("resource")?)
      else
        h.fail("param 'resource' not found")
      end
      try
        h.assert_eq[String]("99", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /api/v1/users/99")
    end

class \nodoc\ iso _TestSplitParamThenStatic is UnitTest
  """Param route first, then static with shared prefix — both resolve."""
  fun name(): String => "router/split param then static"

  fun apply(h: TestHelper) =>
    let param_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "param")
    } val
    let static_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "static")
    } val
    let builder = _RouterBuilder
    // Param route first
    builder.add(stallion.POST, "/a/b/c/user/:id/filter", param_factory, None)
    // Static route second — triggers split from the other direction
    builder.add(stallion.POST, "/a/b/c/login", static_factory, None)
    let router = builder.build()

    match router.lookup(stallion.POST, "/a/b/c/login")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](static_factory, m.factory)
    else
      h.fail("expected match for /a/b/c/login")
    end

    match router.lookup(stallion.POST, "/a/b/c/user/42/filter")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](param_factory, m.factory)
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /a/b/c/user/42/filter")
    end

class \nodoc\ iso _TestSplitAtSegmentBoundary is UnitTest
  """Split where common prefix ends exactly at a `/` boundary."""
  fun name(): String => "router/split at segment boundary"

  fun apply(h: TestHelper) =>
    let list_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "list")
    } val
    let detail_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "detail")
    } val
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/items/list", list_factory, None)
    builder.add(stallion.GET, "/items/:id", detail_factory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/items/list")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](list_factory, m.factory)
    else
      h.fail("expected match for /items/list")
    end

    match router.lookup(stallion.GET, "/items/42")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](detail_factory, m.factory)
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /items/42")
    end

class \nodoc\ iso _TestSplitMidSegmentParam is UnitTest
  """
  Split where divergence is mid-segment, and the new suffix starts with
  static text before reaching a param.
  """
  fun name(): String => "router/split mid-segment param"

  fun apply(h: TestHelper) =>
    let index_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "index")
    } val
    let item_factory: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "item")
    } val
    let builder = _RouterBuilder
    // "index" and "item" share "i" then diverge mid-segment
    builder.add(stallion.GET, "/prefix/index", index_factory, None)
    builder.add(stallion.GET, "/prefix/item/:id", item_factory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/prefix/index")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](index_factory, m.factory)
    else
      h.fail("expected match for /prefix/index")
    end

    match router.lookup(stallion.GET, "/prefix/item/7")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](item_factory, m.factory)
      try
        h.assert_eq[String]("7", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /prefix/item/7")
    end

class \nodoc\ iso _TestDeepNestedParamSharedPrefix is UnitTest
  """Deeply nested param routes sharing a long common prefix all resolve."""
  fun name(): String => "router/deep nested param shared prefix"

  fun apply(h: TestHelper) =>
    let fa: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "a")
    } val
    let fb: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "b")
    } val
    let fc: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "c")
    } val
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/x/y/z/alpha", fa, None)
    builder.add(stallion.GET, "/x/y/z/a/:id", fb, None)
    builder.add(stallion.GET, "/x/y/z/a/:id/sub/:sid", fc, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/x/y/z/alpha")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](fa, m.factory)
    else
      h.fail("expected match for /x/y/z/alpha")
    end

    match router.lookup(stallion.GET, "/x/y/z/a/10")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](fb, m.factory)
      try
        h.assert_eq[String]("10", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /x/y/z/a/10")
    end

    match router.lookup(stallion.GET, "/x/y/z/a/10/sub/20")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](fc, m.factory)
      try
        h.assert_eq[String]("10", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
      try
        h.assert_eq[String]("20", m.params("sid")?)
      else
        h.fail("param 'sid' not found")
      end
    else
      h.fail("expected match for /x/y/z/a/10/sub/20")
    end

// --- Property test: insertion order invariance ---

class \nodoc\ iso _PropertyInsertionOrderInvariance is
  Property1[(Array[USize] val, Array[USize] val)]
  """
  Route lookup results are independent of insertion order.

  Generates two permutations of the same route set and verifies that both
  produce identical lookup results for every registered path.
  """
  fun name(): String => "router/property/insertion order invariance"

  fun gen(): Generator[(Array[USize] val, Array[USize] val)] =>
    // Generate two permutations of indices 0..4 by shuffling
    Generators.zip2[Array[USize] val, Array[USize] val](
      _GenPermutation(5), _GenPermutation(5))

  fun property(sample: (Array[USize] val, Array[USize] val),
    h: PropertyHelper)
  =>
    (let perm_a, let perm_b) = sample

    // Fixed route set mixing static, param, and wildcard patterns
    let routes: Array[(String, String)] val = [
      ("/api/v1/users", "/api/v1/users")
      ("/api/v1/users/:id", "/api/v1/users/42")
      ("/api/v1/items", "/api/v1/items")
      ("/api/v1/items/:id/detail", "/api/v1/items/7/detail")
      ("/api/v1/*rest", "/api/v1/anything/here")
    ]

    let router_a = _build_in_order(routes, perm_a)
    let router_b = _build_in_order(routes, perm_b)

    // Both routers must agree on every lookup path
    for (_, lookup_path) in routes.values() do
      let result_a = router_a.lookup(stallion.GET, lookup_path)
      let result_b = router_b.lookup(stallion.GET, lookup_path)
      match (result_a, result_b)
      | (let _: _RouteMatch, let _: _RouteMatch) => None
      | (None, None) => None
      else
        h.fail("insertion order changed result for " + lookup_path)
      end
    end

  fun _build_in_order(
    routes: Array[(String, String)] val,
    order: Array[USize] val)
    : _Router val
  =>
    let builder = _RouterBuilder
    for idx in order.values() do
      try
        (let pattern, _) = routes(idx)?
        builder.add(stallion.GET, pattern, _NoOpFactory, None)
      else
        _Unreachable()
      end
    end
    builder.build()

primitive \nodoc\ _GenPermutation
  """Generate a random permutation of indices 0..n-1 as val array."""
  fun apply(n: USize): Generator[Array[USize] val] =>
    Generator[Array[USize] val](
      object is GenObj[Array[USize] val]
        let _n: USize = n
        fun generate(r: Randomness): Array[USize] val^ =>
          let a = Array[USize](_n)
          for i in Range(0, _n) do
            a.push(i)
          end
          r.shuffle[USize](a)
          let result = recover iso Array[USize](_n) end
          for v in a.values() do
            result.push(v)
          end
          consume result
      end)

