use "pony_test"
use "pony_check"
use "collections"
use stallion = "stallion"

primitive \nodoc\ _TestRouterList
  fun tests(test: PonyTest) =>
    test(Property1UnitTest[String](_PropertyStaticRouteMatches))
    test(Property1UnitTest[String](_PropertyUnregisteredReturnsMiss))
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
    test(Property1UnitTest[
      (Array[USize] val, Array[USize] val)](
      _PropertyInsertionOrderInvariance))
    test(_TestHeadFallbackInRouter)
    test(_TestInterceptorAccumulation)
    test(_TestMissCarriesInterceptors)
    test(_TestRootMissCarriesInterceptors)
    test(_TestPerRouteInterceptorsMethodSpecific)
    test(_TestValidateGroupsDistinctPrefixes)
    test(_TestValidateGroupsOverlappingPrefixes)
    test(_TestValidateGroupsEmptyPrefix)
    test(_TestValidateGroupsRootPrefix)
    test(_TestValidateGroupsSpecialChars)
    test(_TestParamNameConflictReturnsError)
    test(_TestInterceptorSegmentBoundary)
    test(_TestInterceptorSegmentBoundaryMiss)
    test(_TestInterceptorSegmentBoundaryNestedGroups)
    test(_TestDeepestMissPreservesRicherInterceptors)
    test(_TestSharedParamNameConsistent)
    test(_TestMethodNotAllowed)
    test(_TestMethodNotAllowedAllowHeader)
    test(_TestWildcardMethodIsolation)
    test(_TestWildcardHeadFallback)
    test(_TestParamPriorityOverWildcard)
    test(_TestStaticParamWildcardPriority)
    test(_Test405FallsBackToLowerPriorityMatch)
    test(_Test405FallsBackStaticToParam)
    test(_Test405AllowHeaderScopedToEntryType)
    test(_TestDoubleSlashNormalization)
    test(_TestWildcardDoubleSlashNormalization)
    test(_TestSplitSegmentsEdgeCases)
    test(Property1UnitTest[String](_PropertySplitJoinRoundTrip))
    test(_TestJoinRemainingSegments)
    test(_TestRoutesBeforeInterceptors)
    test(_TestMethodNotAllowedCarriesInterceptors)

// --- Generators ---
primitive \nodoc\ _GenPathSegment
  """
  Generate a single path segment: letters or digits, length 1-10.
  """
  fun apply(): Generator[String] =>
    Generators.ascii(1, 10 where range = ASCIILetters)
      .union[String](Generators.ascii(1, 5 where range = ASCIIDigits))

primitive \nodoc\ _GenStaticPath
  """
  Generate a static path with 1 or 2 segments.
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
      }).union[String](
    _GenPathSegment().map[String]({(a: String): String => "/" + a }))

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
      [ stallion.GET; stallion.POST; stallion.PUT
        stallion.DELETE; stallion.PATCH
        stallion.HEAD; stallion.OPTIONS
      ])

// --- Test factory ---
primitive \nodoc\ _NoOpFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    RequestHandler(consume ctx).respond(stallion.StatusOK, "ok")

// --- Property tests ---
class \nodoc\ iso _PropertyStaticRouteMatches is Property1[String]
  """
  A registered static route always matches.
  """
  fun name(): String => "router/property/static route matches"

  fun gen(): Generator[String] => _GenStaticPath()

  fun property(path: String, h: PropertyHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, path, _NoOpFactory, None)
    let router = builder.build()
    match router.lookup(stallion.GET, path)
    | let m: _RouteMatch =>
      h.assert_eq[USize](0, m.params.size())
    | let _: _RouteMiss =>
      h.fail("expected match for " + path)
    end

class \nodoc\ iso _PropertyUnregisteredReturnsMiss is Property1[String]
  """
  An unregistered path returns _RouteMiss.
  """
  fun name(): String => "router/property/unregistered returns miss"

  fun gen(): Generator[String] => _GenStaticPath()

  fun property(path: String, h: PropertyHelper) =>
    let router = _RouterBuilder.build()
    match \exhaustive\ router.lookup(stallion.GET, path)
    | let _: _RouteMiss => None
    | let _: _RouteMatch =>
      h.fail("expected miss for " + path + " on empty router")
    | let _: _MethodNotAllowed =>
      h.fail("expected miss for " + path + " on empty router")
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
    builder.add(stallion.GET, pattern, _NoOpFactory, None)
    let router = builder.build()

    let lookup_path: String val = prefix + "/testvalue"
    match router.lookup(stallion.GET, lookup_path)
    | let m: _RouteMatch =>
      try
        h.assert_eq[String]("testvalue", m.params(param_name)?)
      else
        h.fail("param not found in match")
      end
    | let _: _RouteMiss =>
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
    | let _: _RouteMiss =>
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
    // Skip HEAD — it falls back to GET in the shared tree
    if method is stallion.HEAD then return end

    let builder = _RouterBuilder
    builder.add(method, "/test", _NoOpFactory, None)
    let router = builder.build()

    // Should match the registered method
    match router.lookup(method, "/test")
    | let _: _RouteMatch => None
    else
      h.fail("expected match for registered method")
    end

    // Should return 405 for a different method (excluding HEAD→GET)
    let other: stallion.Method =
      if method is stallion.GET then
        stallion.POST
      else
        stallion.GET
      end
    match \exhaustive\ router.lookup(other, "/test")
    | let _: _MethodNotAllowed => None
    | let _: _RouteMatch =>
      h.fail("should not match different method")
    | let _: _RouteMiss =>
      h.fail("should be 405, not 404")
    end

class \nodoc\ iso _PropertyWildcardCapture is Property1[String]
  """
  `*name` captures the remainder of the path.
  """
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
    | let _: _RouteMiss =>
      h.fail("expected match")
    end

// --- Example-based tests ---
class \nodoc\ iso _TestStaticPriorityOverParam is UnitTest
  """
  `/users/new` matches static before `/users/:id`.
  """
  fun name(): String => "router/static priority over param"

  fun apply(h: TestHelper) =>
    let static_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "static")
      } val
    let param_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "param")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.GET, "/users/:id", param_factory, None)
    builder.add(
      stallion.GET, "/users/new", static_factory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/users/new")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        static_factory, m.factory)
    | let _: _RouteMiss =>
      h.fail("expected match for /users/new")
    end

    match router.lookup(stallion.GET, "/users/42")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        param_factory, m.factory)
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for /users/42")
    end

class \nodoc\ iso _TestRootPath is UnitTest
  """
  Root path `/` matches.
  """
  fun name(): String => "router/root path"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/", _NoOpFactory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/")
    | let _: _RouteMatch => None
    | let _: _RouteMiss =>
      h.fail("expected match for /")
    end

class \nodoc\ iso _TestOverlappingPrefixes is UnitTest
  """
  Multiple routes with overlapping prefixes dispatch correctly.
  """
  fun name(): String => "router/overlapping prefixes"

  fun apply(h: TestHelper) =>
    let f1: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "v1")
      } val
    let f2: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "v2")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.GET, "/api/v1/users", f1, None)
    builder.add(
      stallion.GET, "/api/v2/users", f2, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/api/v1/users")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](f1, m.factory)
    | let _: _RouteMiss =>
      h.fail("expected match for /api/v1/users")
    end

    match router.lookup(stallion.GET, "/api/v2/users")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](f2, m.factory)
    | let _: _RouteMiss =>
      h.fail("expected match for /api/v2/users")
    end

class \nodoc\ iso _TestWildcardSingleSegment is UnitTest
  """
  Wildcard captures a single segment.
  """
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
    | let _: _RouteMiss =>
      h.fail("expected match for /files/readme.txt")
    end

    // /files/ normalizes to /files which has no remainder for the wildcard
    match router.lookup(stallion.GET, "/files/")
    | let _: _RouteMatch =>
      h.fail(
        "should not match /files/ "
          + "(normalizes to /files, no wildcard content)")
    end

class \nodoc\ iso _TestTrailingSlashNormalization is UnitTest
  """
  `/users/` and `/users` match the same route.
  """
  fun name(): String => "router/trailing slash normalization"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/users", _NoOpFactory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/users")
    | let _: _RouteMatch => None
    | let _: _RouteMiss =>
      h.fail("expected match for /users")
    end

    match router.lookup(stallion.GET, "/users/")
    | let _: _RouteMatch => None
    | let _: _RouteMiss =>
      h.fail("expected match for /users/ (trailing slash)")
    end

class \nodoc\ iso _TestParamPriorityOverWildcard is UnitTest
  """
  Param child is tried before wildcard at the same node.
  """
  fun name(): String => "router/param priority over wildcard"

  fun apply(h: TestHelper) =>
    let param_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "param")
      } val
    let wildcard_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "wildcard")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.GET, "/files/:id", param_factory, None)
    builder.add(
      stallion.GET,
      "/files/*path",
      wildcard_factory,
      None)
    let router = builder.build()

    // Single segment — param wins over wildcard
    match router.lookup(
      stallion.GET, "/files/readme.txt")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        param_factory, m.factory)
      try
        h.assert_eq[String](
          "readme.txt", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail(
        "expected param match for /files/readme.txt")
    end

    // Multi-segment — param can't match, wildcard takes it
    match router.lookup(
      stallion.GET, "/files/css/style.css")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        wildcard_factory, m.factory)
      try
        h.assert_eq[String](
          "css/style.css", m.params("path")?)
      else
        h.fail("wildcard param 'path' not found")
      end
    else
      h.fail(
        "expected wildcard match for /files/css/style.css")
    end

class \nodoc\ iso _TestStaticParamWildcardPriority is UnitTest
  """
  Full three-level priority: static > param > wildcard.
  """
  fun name(): String => "router/static param wildcard priority"

  fun apply(h: TestHelper) =>
    let static_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "static")
      } val
    let param_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "param")
      } val
    let wildcard_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "wildcard")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.GET,
      "/files/special",
      static_factory,
      None)
    builder.add(
      stallion.GET, "/files/:id", param_factory, None)
    builder.add(
      stallion.GET,
      "/files/*path",
      wildcard_factory,
      None)
    let router = builder.build()

    // Exact static match — highest priority
    match router.lookup(
      stallion.GET, "/files/special")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        static_factory, m.factory)
    else
      h.fail(
        "expected static match for /files/special")
    end

    // Single segment, not "special" — param wins
    match router.lookup(stallion.GET, "/files/other")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        param_factory, m.factory)
    else
      h.fail("expected param match for /files/other")
    end

    // Multi-segment — only wildcard can match
    match router.lookup(stallion.GET, "/files/a/b/c")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        wildcard_factory, m.factory)
    else
      h.fail("expected wildcard match for /files/a/b/c")
    end

class \nodoc\ iso _Test405FallsBackToLowerPriorityMatch is UnitTest
  """

  405 from param falls back to wildcard match.

  POST /files/:id + GET /files/*path — GET /files/readme.txt should match
  the wildcard, not return 405 from the param branch.
  """

  fun name(): String => "router/405 falls back to lower priority match"

  fun apply(h: TestHelper) =>
    let param_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "param")
      } val
    let wildcard_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "wildcard")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.POST,
      "/files/:id",
      param_factory,
      None)
    builder.add(
      stallion.GET,
      "/files/*path",
      wildcard_factory,
      None)
    let router = builder.build()

    // GET should fall through param to wildcard
    match \exhaustive\ router.lookup(
      stallion.GET, "/files/readme.txt")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        wildcard_factory, m.factory)
      try
        h.assert_eq[String](
          "readme.txt", m.params("path")?)
      else
        h.fail("wildcard param 'path' not found")
      end
    | let _: _MethodNotAllowed =>
      h.fail(
        "should match GET wildcard, "
          + "not return 405 from POST param")
    | let _: _RouteMiss =>
      h.fail("expected match")
    end

    // POST should match param (higher priority)
    match router.lookup(
      stallion.POST, "/files/readme.txt")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        param_factory, m.factory)
    else
      h.fail("expected POST param match")
    end

class \nodoc\ iso _Test405FallsBackStaticToParam is UnitTest
  """

  405 from static falls back to param match.

  POST /users/new + GET /users/:id — GET /users/new should match the param
  with id="new", not return 405 from the static branch.
  """

  fun name(): String => "router/405 falls back static to param"

  fun apply(h: TestHelper) =>
    let static_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "static")
      } val
    let param_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "param")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.POST,
      "/users/new",
      static_factory,
      None)
    builder.add(
      stallion.GET, "/users/:id", param_factory, None)
    let router = builder.build()

    // GET /users/new: POST-only → falls back to param
    match \exhaustive\ router.lookup(
      stallion.GET, "/users/new")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        param_factory, m.factory)
      try
        h.assert_eq[String](
          "new", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    | let _: _MethodNotAllowed =>
      h.fail(
        "should match GET param, "
          + "not return 405 from POST static")
    | let _: _RouteMiss =>
      h.fail("expected match")
    end

    // POST /users/new: static matches
    match router.lookup(
      stallion.POST, "/users/new")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](
        static_factory, m.factory)
    else
      h.fail("expected POST static match")
    end

class \nodoc\ iso _Test405AllowHeaderScopedToEntryType is UnitTest
  """

  Allow header on 405 lists only methods from the matching entry type.

  GET /files + POST /files/*path → DELETE /files gets Allow: GET, HEAD
  (from exact-path entries only), not GET, HEAD, POST (which would leak
  wildcard methods).
  """

  fun name(): String => "router/405 allow header scoped to entry type"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/files", _NoOpFactory, None)
    builder.add(stallion.POST, "/files/*path", _NoOpFactory, None)
    let router = builder.build()

    // DELETE /files → 405 from exact-path entries (GET only)
    match \exhaustive\ router.lookup(stallion.DELETE, "/files")
    | let na: _MethodNotAllowed =>
      // Should have GET and HEAD (implicit), but NOT POST
      var has_get = false
      var has_head = false
      var has_post = false
      for m in na.allowed_methods.values() do
        if m == "GET" then has_get = true end
        if m == "HEAD" then has_head = true end
        if m == "POST" then has_post = true end
      end
      h.assert_true(has_get, "Allow should include GET")
      h.assert_true(has_head, "Allow should include HEAD")
      h.assert_false(
        has_post,
        "Allow must NOT include POST "
          + "(wildcard method, different resource)")
    | let _: _RouteMatch =>
      h.fail("DELETE should not match")
    | let _: _RouteMiss =>
      h.fail("should be 405, not 404")
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

  fun property(
    sample: (Array[USize] val, Array[USize] val),
    h: PropertyHelper)
  =>
    (let perm_a, let perm_b) = sample

    // Distinct factories per route
    let f0: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "0")
      } val
    let f1: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "1")
      } val
    let f2: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "2")
      } val
    let f3: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "3")
      } val
    let f4: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "4")
      } val

    // Fixed route set: static, param, wildcard
    let routes:
      Array[(String, String, HandlerFactory)] val
    =
      [ ("/api/v1/users", "/api/v1/users", f0)
        ("/api/v1/users/:id", "/api/v1/users/42", f1)
        ("/api/v1/items", "/api/v1/items", f2)
        ( "/api/v1/items/:id/detail"
        , "/api/v1/items/7/detail"
        , f3)
        ( "/api/v1/*rest"
        , "/api/v1/anything/here"
        , f4)
      ]

    let router_a = _build_in_order(routes, perm_a)
    let router_b = _build_in_order(routes, perm_b)

    // Both must agree on every lookup path
    for (_, lookup_path, _) in routes.values() do
      let result_a =
        router_a.lookup(stallion.GET, lookup_path)
      let result_b =
        router_b.lookup(stallion.GET, lookup_path)
      match (result_a, result_b)
      | (let ma: _RouteMatch, let mb: _RouteMatch) =>
        h.assert_true(
          ma.factory is mb.factory,
          "insertion order changed matched route for "
            + lookup_path)
      | (let _: _RouteMiss, let _: _RouteMiss) =>
        None
      | ( let _: _MethodNotAllowed
        , let _: _MethodNotAllowed) =>
        None
      else
        h.fail(
          "insertion order changed result type for "
            + lookup_path)
      end
    end

  fun _build_in_order(
    routes: Array[(String, String, HandlerFactory)] val,
    order: Array[USize] val)
    : _Router val
  =>
    let builder = _RouterBuilder
    for idx in order.values() do
      try
        (let pattern, _, let factory) = routes(idx)?
        builder.add(stallion.GET, pattern, factory, None)
      else
        _Unreachable()
      end
    end
    builder.build()

primitive \nodoc\ _GenPermutation
  """
  Generate a random permutation of indices 0..n-1 as val array.
  """
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

// --- New tests for shared path tree ---
class \nodoc\ iso _TestHeadFallbackInRouter is UnitTest
  """
  HEAD falls back to GET handler in a single tree traversal.
  """
  fun name(): String => "router/HEAD fallback in router"

  fun apply(h: TestHelper) =>
    let get_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "get")
      } val
    let head_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "head")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.GET, "/fallback", get_factory, None)
    builder.add(
      stallion.HEAD,
      "/explicit",
      head_factory,
      None)
    builder.add(
      stallion.GET, "/explicit", get_factory, None)
    let router = builder.build()

    // HEAD to /fallback should resolve to GET handler
    match router.lookup(stallion.HEAD, "/fallback")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](get_factory, m.factory)
    | let _: _RouteMiss =>
      h.fail("HEAD should fall back to GET for /fallback")
    end

    // HEAD to /explicit should resolve to HEAD handler
    match router.lookup(stallion.HEAD, "/explicit")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](head_factory, m.factory)
    | let _: _RouteMiss =>
      h.fail("expected match for HEAD /explicit")
    end

class \nodoc\ iso _TestInterceptorAccumulation is UnitTest
  """
  Interceptors on a path node accumulate into matched routes under it.
  """
  fun name(): String => "router/interceptor accumulation"

  fun apply(h: TestHelper) =>
    let interceptor: RequestInterceptor val = _PassInterceptor
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: interceptor] end
    let builder = _RouterBuilder
    builder.add_interceptors("/api", interceptors, None)
    builder.add(stallion.GET, "/api/users", _NoOpFactory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/api/users")
    | let m: _RouteMatch =>
      match m.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(
            ints(0)? is interceptor,
            "accumulated interceptor should be "
              + "the one registered on /api")
        else
          h.fail("interceptor access failed")
        end
      else
        h.fail(
          "expected interceptors on matched route")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for /api/users")
    end

class \nodoc\ iso _TestMissCarriesInterceptors is UnitTest
  """
  A miss under a group carries the group's accumulated interceptors.
  """
  fun name(): String => "router/miss carries interceptors"

  fun apply(h: TestHelper) =>
    let interceptor: RequestInterceptor val = _PassInterceptor
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: interceptor] end
    let resp_interceptor: ResponseInterceptor val = _NoOpResponseInterceptor
    let resp_interceptors: Array[ResponseInterceptor val] val =
      recover val [as ResponseInterceptor val: resp_interceptor] end
    let builder = _RouterBuilder
    builder.add_interceptors("/api", interceptors, resp_interceptors)
    builder.add(stallion.GET, "/api/users", _NoOpFactory, None)
    let router = builder.build()

    // Miss under /api should carry /api's interceptors
    match router.lookup(stallion.GET, "/api/nonexistent")
    | let miss: _RouteMiss =>
      match miss.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(
            ints(0)? is interceptor,
            "miss should carry the request "
              + "interceptor from /api")
        else
          h.fail("interceptor access failed")
        end
      else
        h.fail(
          "expected request interceptors on miss")
      end
      match miss.response_interceptors
      | let ris: Array[ResponseInterceptor val] val =>
        h.assert_eq[USize](1, ris.size())
        try
          h.assert_true(
            ris(0)? is resp_interceptor,
            "miss should carry the response "
              + "interceptor from /api")
        else
          h.fail("response interceptor access failed")
        end
      else
        h.fail(
          "expected response interceptors on miss")
      end
    | let _: _RouteMatch =>
      h.fail("expected miss for /api/nonexistent")
    end

class \nodoc\ iso _TestRootMissCarriesInterceptors is UnitTest
  """
  A miss at the root carries root-level interceptors.
  """
  fun name(): String => "router/root miss carries interceptors"

  fun apply(h: TestHelper) =>
    let interceptor: RequestInterceptor val = _PassInterceptor
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: interceptor] end
    let builder = _RouterBuilder
    builder.add_interceptors("", interceptors, None)
    builder.add(stallion.GET, "/exists", _NoOpFactory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/nonexistent")
    | let miss: _RouteMiss =>
      match miss.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(
            ints(0)? is interceptor,
            "root miss should carry "
              + "the root interceptor")
        else
          h.fail("interceptor access failed")
        end
      else
        h.fail("expected root interceptors on miss")
      end
    | let _: _RouteMatch =>
      h.fail("expected miss for /nonexistent")
    end

class \nodoc\ iso _TestPerRouteInterceptorsMethodSpecific is UnitTest
  """
  Per-route interceptors are method-specific at the same leaf.
  """
  fun name(): String => "router/per-route interceptors method-specific"

  fun apply(h: TestHelper) =>
    let get_interceptor: RequestInterceptor val = _PassInterceptor
    let get_interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: get_interceptor] end
    let post_interceptor: RequestInterceptor val = _RejectInterceptor
    let post_interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: post_interceptor] end

    let builder = _RouterBuilder
    builder.add(
      stallion.GET,
      "/api/users",
      _NoOpFactory,
      None,
      get_interceptors)
    builder.add(
      stallion.POST,
      "/api/users",
      _NoOpFactory,
      None,
      post_interceptors)
    let router = builder.build()

    match router.lookup(stallion.GET, "/api/users")
    | let m: _RouteMatch =>
      match m.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(ints(0)? is get_interceptor)
        else
          h.fail("unexpected interceptor on GET")
        end
      else
        h.fail("expected interceptors on GET")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for GET /api/users")
    end

    match router.lookup(stallion.POST, "/api/users")
    | let m: _RouteMatch =>
      match m.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(ints(0)? is post_interceptor)
        else
          h.fail("unexpected interceptor on POST")
        end
      else
        h.fail("expected interceptors on POST")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for POST /api/users")
    end

class \nodoc\ iso _TestValidateGroupsDistinctPrefixes is UnitTest
  """
  Distinct sibling and nested group prefixes pass validation.
  """
  fun name(): String => "router/validate groups distinct prefixes"

  fun apply(h: TestHelper) =>
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end
    let infos: Array[_GroupInfo] ref = Array[_GroupInfo]
    infos.push(_GroupInfo("/api", interceptors, None))
    infos.push(_GroupInfo("/admin", interceptors, None))
    infos.push(_GroupInfo("/api/v1", interceptors, None))
    h.assert_true(
      _ValidateGroups(infos) is None,
      "distinct prefixes should pass validation")

class \nodoc\ iso _TestValidateGroupsOverlappingPrefixes is UnitTest
  """
  Overlapping group prefixes produce a ConfigError.
  """
  fun name(): String => "router/validate groups overlapping prefixes"

  fun apply(h: TestHelper) =>
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end
    let infos: Array[_GroupInfo] ref = Array[_GroupInfo]
    infos.push(_GroupInfo("/api", interceptors, None))
    infos.push(_GroupInfo("/api", interceptors, None))
    match _ValidateGroups(infos)
    | let err: ConfigError =>
      h.assert_true(err.message.contains("Overlapping"))
    else
      h.fail("overlapping prefixes should produce ConfigError")
    end

class \nodoc\ iso _TestValidateGroupsEmptyPrefix is UnitTest
  """
  Empty group prefix produces a ConfigError.
  """
  fun name(): String => "router/validate groups empty prefix"

  fun apply(h: TestHelper) =>
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end
    let infos: Array[_GroupInfo] ref = Array[_GroupInfo]
    infos.push(_GroupInfo("", interceptors, None))
    match _ValidateGroups(infos)
    | let err: ConfigError =>
      h.assert_true(err.message.contains("app-level interceptors"))
    else
      h.fail("empty prefix should produce ConfigError")
    end

class \nodoc\ iso _TestValidateGroupsRootPrefix is UnitTest
  """
  RouteGroup("/") with interceptors produces a ConfigError.
  """
  fun name(): String => "router/validate groups root prefix"

  fun apply(h: TestHelper) =>
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end
    let infos: Array[_GroupInfo] ref = Array[_GroupInfo]
    infos.push(_GroupInfo("/", interceptors, None))
    match _ValidateGroups(infos)
    | let err: ConfigError =>
      h.assert_true(err.message.contains("app-level interceptors"))
    else
      h.fail("root prefix should produce ConfigError")
    end

class \nodoc\ iso _TestValidateGroupsSpecialChars is UnitTest
  """
  Special characters in group prefix produce a ConfigError.
  """
  fun name(): String => "router/validate groups special chars"

  fun apply(h: TestHelper) =>
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end

    // Colon in prefix
    let infos_colon: Array[_GroupInfo] ref = Array[_GroupInfo]
    infos_colon.push(_GroupInfo("/:org", interceptors, None))
    match _ValidateGroups(infos_colon)
    | let err: ConfigError =>
      h.assert_true(err.message.contains("':'"))
    else
      h.fail("colon in prefix should produce ConfigError")
    end

    // Wildcard in prefix
    let infos_star: Array[_GroupInfo] ref = Array[_GroupInfo]
    infos_star.push(_GroupInfo("/files/*path", interceptors, None))
    match _ValidateGroups(infos_star)
    | let err: ConfigError =>
      h.assert_true(err.message.contains("'*'"))
    else
      h.fail("wildcard in prefix should produce ConfigError")
    end

class \nodoc\ iso _TestParamNameConflictReturnsError is UnitTest
  """
  Conflicting param names at the same position produce a ConfigError.
  """
  fun name(): String => "router/param name conflict returns error"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/users/:userId", _NoOpFactory, None)
    builder.add(stallion.POST, "/users/:id", _NoOpFactory, None)
    match builder.first_error()
    | let err: ConfigError =>
      h.assert_true(err.message.contains("Conflicting param names"))
      h.assert_true(err.message.contains("userId"))
      h.assert_true(err.message.contains("id"))
    else
      h.fail("conflicting param names should produce ConfigError")
    end

class \nodoc\ iso _TestInterceptorSegmentBoundary is UnitTest
  """

  Group interceptors at /api must NOT leak to /api-docs.

  In the segment trie, `/api` and `/api-docs` are distinct children of the
  root node (`"api"` vs `"api-docs"`). Interceptors registered on the `/api`
  node propagate only to its children, not to sibling segments.
  """

  fun name(): String => "router/interceptor segment boundary"

  fun apply(h: TestHelper) =>
    let interceptor: RequestInterceptor val = _PassInterceptor
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: interceptor] end
    let builder = _RouterBuilder
    builder.add_interceptors("/api", interceptors, None)
    builder.add(stallion.GET, "/api/users", _NoOpFactory, None)
    builder.add(stallion.GET, "/api-docs", _NoOpFactory, None)
    let router = builder.build()

    // /api/users is under the /api group — should get interceptors
    match router.lookup(stallion.GET, "/api/users")
    | let m: _RouteMatch =>
      match m.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](
          1,
          ints.size(),
          "/api/users should have "
            + "group interceptors")
      else
        h.fail(
          "/api/users should have interceptors")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for /api/users")
    end

    // /api-docs is NOT under /api — must NOT get interceptors
    match router.lookup(stallion.GET, "/api-docs")
    | let m: _RouteMatch =>
      h.assert_true(
        m.interceptors is None,
        "/api-docs must not inherit "
          + "/api group interceptors")
    | let _: _RouteMiss =>
      h.fail("expected match for /api-docs")
    end

class \nodoc\ iso _TestInterceptorSegmentBoundaryMiss is UnitTest
  """

  A 404 miss at a sibling path (/api-unknown) must NOT carry group
  interceptors from /api.
  """

  fun name(): String => "router/interceptor segment boundary miss"

  fun apply(h: TestHelper) =>
    let interceptor: RequestInterceptor val = _PassInterceptor
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: interceptor] end
    let builder = _RouterBuilder
    builder.add_interceptors("/api", interceptors, None)
    builder.add(stallion.GET, "/api/users", _NoOpFactory, None)
    builder.add(stallion.GET, "/api-docs", _NoOpFactory, None)
    let router = builder.build()

    // Miss under /api/ — SHOULD carry /api's interceptors
    match router.lookup(stallion.GET, "/api/nonexistent")
    | let miss: _RouteMiss =>
      match miss.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](
          1,
          ints.size(),
          "/api/nonexistent should carry "
            + "group interceptors")
      else
        h.fail(
          "/api/nonexistent miss should "
            + "have interceptors")
      end
    | let _: _RouteMatch =>
      h.fail("expected miss for /api/nonexistent")
    end

    // Miss at /api-unknown — must NOT carry /api's interceptors
    match router.lookup(stallion.GET, "/api-unknown")
    | let miss: _RouteMiss =>
      h.assert_true(
        miss.interceptors is None,
        "/api-unknown miss must not inherit "
          + "/api group interceptors")
    | let _: _RouteMatch =>
      h.fail("expected miss for /api-unknown")
    end

class \nodoc\ iso _TestInterceptorSegmentBoundaryNestedGroups is UnitTest
  """

  App-level interceptors propagate everywhere. Group interceptors at /api
  propagate to /api/admin/users but not to /api-docs.
  """

  fun name(): String => "router/interceptor segment boundary nested groups"

  fun apply(h: TestHelper) =>
    let app_interceptor: RequestInterceptor val = _PassInterceptor
    let app_interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: app_interceptor] end
    let api_interceptor: RequestInterceptor val = _RejectInterceptor
    let api_interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: api_interceptor] end

    let builder = _RouterBuilder
    builder.add_interceptors("", app_interceptors, None)
    builder.add_interceptors("/api", api_interceptors, None)
    builder.add(stallion.GET, "/api/users", _NoOpFactory, None)
    builder.add(stallion.GET, "/api-docs", _NoOpFactory, None)
    let router = builder.build()

    // /api/users gets app + api interceptors (2 total)
    match router.lookup(stallion.GET, "/api/users")
    | let m: _RouteMatch =>
      match m.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](
          2,
          ints.size(),
          "/api/users should have "
            + "app + api interceptors")
      else
        h.fail(
          "/api/users should have interceptors")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for /api/users")
    end

    // /api-docs gets ONLY app interceptors (1 total)
    match router.lookup(stallion.GET, "/api-docs")
    | let m: _RouteMatch =>
      match m.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](
          1,
          ints.size(),
          "/api-docs should have only "
            + "app interceptors")
        try
          h.assert_true(
            ints(0)? is app_interceptor,
            "/api-docs should have app "
              + "interceptor, not api interceptor")
        else
          h.fail("interceptor access failed")
        end
      else
        h.fail(
          "/api-docs should have app interceptors")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for /api-docs")
    end

class \nodoc\ iso _TestDeepestMissPreservesRicherInterceptors is UnitTest
  """

  When static and param children both miss, the miss with richer interceptors
  wins.

  Group [A] on /api, group [B] on /api/users/new. Routes: GET
  /api/users/new/settings and GET /api/users/:id. Lookup for GET
  /api/users/new/nonexistent — static child reaches depth with [A, B] but
  misses, param child :id misses with only [A]. The 404 must carry [A, B].
  """

  fun name(): String => "router/deepest miss preserves richer interceptors"

  fun apply(h: TestHelper) =>
    let int_a: RequestInterceptor val = _PassInterceptor
    let ints_a: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: int_a] end
    let int_b: RequestInterceptor val = _RejectInterceptor
    let ints_b: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: int_b] end

    let builder = _RouterBuilder
    builder.add_interceptors("/api", ints_a, None)
    builder.add_interceptors("/api/users/new", ints_b, None)
    builder.add(stallion.GET, "/api/users/new/settings", _NoOpFactory, None)
    builder.add(stallion.GET, "/api/users/:id", _NoOpFactory, None)
    let router = builder.build()

    // /api/users/new/nonexistent: static child "new" reaches depth with
    // [A, B] but misses. Param :id misses with [A]. Must keep [A, B].
    match router.lookup(stallion.GET, "/api/users/new/nonexistent")
    | let miss: _RouteMiss =>
      match miss.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](
          2,
          ints.size(),
          "miss should carry [A, B] from "
            + "deeper static traversal, not [A]")
      else
        h.fail("expected interceptors on miss")
      end
    | let _: _RouteMatch =>
      h.fail("expected miss for /api/users/new/nonexistent")
    end

class \nodoc\ iso _TestSharedParamNameConsistent is UnitTest
  """

  Multiple methods at the same param position with the same name works.

  GET /users/:id and POST /users/:id share a param child — the name must
  match. Mismatched names (e.g., :userId vs :id) would panic at startup.
  """

  fun name(): String => "router/shared param name consistent"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/users/:id", _NoOpFactory, None)
    builder.add(stallion.POST, "/users/:id", _NoOpFactory, None)
    let router = builder.build()

    match router.lookup(stallion.GET, "/users/42")
    | let m: _RouteMatch =>
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found on GET")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for GET /users/42")
    end

    match router.lookup(stallion.POST, "/users/42")
    | let m: _RouteMatch =>
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found on POST")
      end
    | let _: _RouteMiss =>
      h.fail("expected match for POST /users/42")
    end

class \nodoc\ iso _TestDoubleSlashNormalization is UnitTest
  """

  Double slashes are normalized: `/users//42/details` matches
  `/users/:id/details` with `id` = `"42"`.
  """

  fun name(): String => "router/double slash normalization"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/users/:id/details", _NoOpFactory, None)
    let router = builder.build()

    // Normal param — matches
    match router.lookup(stallion.GET, "/users/42/details")
    | let m: _RouteMatch =>
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /users/42/details")
    end

    // Double slash normalized: /users//42/details → segments
    // ["users", "42", "details"]
    match router.lookup(stallion.GET, "/users//42/details")
    | let m: _RouteMatch =>
      try
        h.assert_eq[String]("42", m.params("id")?)
      else
        h.fail("param 'id' not found")
      end
    else
      h.fail("expected match for /users//42/details (double slash normalized)")
    end

    // /users//details is 2 segments ["users", "details"] — misses the
    // 3-segment route /users/:id/details
    match \exhaustive\ router.lookup(stallion.GET, "/users//details")
    | let _: _RouteMiss => None
    | let _: _RouteMatch =>
      h.fail("/users//details should miss (only 2 segments)")
    | let _: _MethodNotAllowed => None
    end

class \nodoc\ iso _TestWildcardDoubleSlashNormalization is UnitTest
  """

  Wildcard captures normalize double slashes in the captured value.

  A request for `/files/a//b/c` produces a wildcard value of `"a/b/c"`,
  not `"a//b/c"`, because `_SplitSegments` skips empty segments before
  the wildcard remainder is reconstructed.
  """

  fun name(): String => "router/wildcard double slash normalization"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/files/*path", _NoOpFactory, None)
    let router = builder.build()

    // Double slash in wildcard portion — normalized in captured value
    match router.lookup(stallion.GET, "/files/a//b/c")
    | let m: _RouteMatch =>
      try
        h.assert_eq[String](
          "a/b/c",
          m.params("path")?,
          "wildcard should normalize "
            + "double slash to single")
      else
        h.fail("wildcard param 'path' not found")
      end
    else
      h.fail("expected match for /files/a//b/c")
    end

    // Triple slash
    match router.lookup(stallion.GET, "/files/x///y")
    | let m: _RouteMatch =>
      try
        h.assert_eq[String](
          "x/y",
          m.params("path")?,
          "wildcard should normalize triple slash")
      else
        h.fail("wildcard param 'path' not found")
      end
    else
      h.fail("expected match for /files/x///y")
    end

class \nodoc\ iso _TestMethodNotAllowed is UnitTest
  """
  Path exists but method doesn't → _MethodNotAllowed, not _RouteMiss.
  """
  fun name(): String => "router/method not allowed"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.POST, "/api/users", _NoOpFactory, None)
    let router = builder.build()

    // GET to a POST-only path → 405
    match \exhaustive\ router.lookup(stallion.GET, "/api/users")
    | let na: _MethodNotAllowed => None
    | let _: _RouteMatch =>
      h.fail("should not match GET on POST-only route")
    | let _: _RouteMiss =>
      h.fail("should be 405, not 404 — path exists")
    end

    // Nonexistent path → 404
    match \exhaustive\ router.lookup(stallion.GET, "/api/nonexistent")
    | let _: _RouteMiss => None
    | let _: _RouteMatch =>
      h.fail("should not match nonexistent path")
    | let _: _MethodNotAllowed =>
      h.fail("should be 404, not 405 — path doesn't exist")
    end

class \nodoc\ iso _TestMethodNotAllowedAllowHeader is UnitTest
  """
  _MethodNotAllowed carries the correct allowed methods list.
  """
  fun name(): String => "router/method not allowed allow header"

  fun apply(h: TestHelper) =>
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/api/users", _NoOpFactory, None)
    builder.add(stallion.POST, "/api/users", _NoOpFactory, None)
    let router = builder.build()

    // DELETE to a GET+POST path → 405 with Allow: GET, POST, HEAD
    match \exhaustive\ router.lookup(stallion.DELETE, "/api/users")
    | let na: _MethodNotAllowed =>
      // Should have GET, POST, and HEAD (implicit from GET)
      h.assert_eq[USize](3, na.allowed_methods.size())
      var has_get = false
      var has_post = false
      var has_head = false
      for m in na.allowed_methods.values() do
        if m == "GET" then has_get = true end
        if m == "POST" then has_post = true end
        if m == "HEAD" then has_head = true end
      end
      h.assert_true(has_get, "Allow should include GET")
      h.assert_true(has_post, "Allow should include POST")
      h.assert_true(has_head, "Allow should include HEAD (implicit from GET)")
    | let _: _RouteMatch =>
      h.fail("should not match DELETE on GET+POST route")
    | let _: _RouteMiss =>
      h.fail("should be 405, not 404")
    end

class \nodoc\ iso _TestWildcardMethodIsolation is UnitTest
  """
  Wildcard routes are method-isolated — POST wildcard doesn't match GET.
  """
  fun name(): String => "router/wildcard method isolation"

  fun apply(h: TestHelper) =>
    let post_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "post")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.POST,
      "/files/*path",
      post_factory,
      None)
    let router = builder.build()

    // POST matches
    match router.lookup(stallion.POST, "/files/readme.txt")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](post_factory, m.factory)
      try
        h.assert_eq[String]("readme.txt", m.params("path")?)
      else
        h.fail("wildcard param 'path' not found")
      end
    else
      h.fail("expected POST match for /files/readme.txt")
    end

    // GET does not match — wildcard entries are method-keyed → 405
    match \exhaustive\ router.lookup(stallion.GET, "/files/readme.txt")
    | let na: _MethodNotAllowed =>
      var has_post = false
      for m in na.allowed_methods.values() do
        if m == "POST" then has_post = true end
      end
      h.assert_true(has_post, "Allow should include POST")
    | let _: _RouteMatch =>
      h.fail("GET should not match POST-only wildcard")
    | let _: _RouteMiss =>
      h.fail("should be 405, not 404 — wildcard path exists for POST")
    end

class \nodoc\ iso _TestWildcardHeadFallback is UnitTest
  """
  HEAD falls back to GET for wildcard routes.
  """
  fun name(): String => "router/wildcard HEAD fallback"

  fun apply(h: TestHelper) =>
    let get_factory: HandlerFactory =
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "get")
      } val
    let builder = _RouterBuilder
    builder.add(
      stallion.GET,
      "/files/*path",
      get_factory,
      None)
    let router = builder.build()

    // HEAD falls back to GET wildcard
    match router.lookup(stallion.HEAD, "/files/readme.txt")
    | let m: _RouteMatch =>
      h.assert_is[HandlerFactory](get_factory, m.factory)
      try
        h.assert_eq[String]("readme.txt", m.params("path")?)
      else
        h.fail("wildcard param 'path' not found")
      end
    else
      h.fail("HEAD should fall back to GET wildcard")
    end

// --- _SplitSegments / _JoinRemainingSegments tests ---
class \nodoc\ iso _TestSplitSegmentsEdgeCases is UnitTest
  """

  `_SplitSegments` edge cases: root, empty, single segment, double slashes,
  triple slashes, param/wildcard markers, and registration-path normalization.
  """

  fun name(): String => "router/split segments edge cases"

  fun apply(h: TestHelper) =>
    // Root path → empty
    let root = _SplitSegments("/")
    h.assert_eq[USize](0, root.size(), "/ should produce 0 segments")

    // Empty string → empty
    let empty = _SplitSegments("")
    h.assert_eq[USize](0, empty.size(), "empty should produce 0 segments")

    // Single segment
    let single = _SplitSegments("/users")
    h.assert_eq[USize](1, single.size())
    try
      h.assert_eq[String]("users", single(0)?)
    else
      h.fail("single segment access failed")
    end

    // Multi-segment
    let multi = _SplitSegments("/api/v1/users")
    h.assert_eq[USize](3, multi.size())
    try
      h.assert_eq[String]("api", multi(0)?)
      h.assert_eq[String]("v1", multi(1)?)
      h.assert_eq[String]("users", multi(2)?)
    else
      h.fail("multi segment access failed")
    end

    // Double slash → empty segment skipped
    let double = _SplitSegments("/api//users")
    h.assert_eq[USize](
      2,
      double.size(),
      "double slash should collapse to 2 segments")
    try
      h.assert_eq[String]("api", double(0)?)
      h.assert_eq[String]("users", double(1)?)
    else
      h.fail("double slash segment access failed")
    end

    // Triple slash
    let triple = _SplitSegments("/a///b")
    h.assert_eq[USize](
      2,
      triple.size(),
      "triple slash should collapse to 2 segments")
    try
      h.assert_eq[String]("a", triple(0)?)
      h.assert_eq[String]("b", triple(1)?)
    else
      h.fail("triple slash segment access failed")
    end

    // Param and wildcard markers are preserved as segment content
    let params = _SplitSegments("/users/:id/posts/*rest")
    h.assert_eq[USize](4, params.size())
    try
      h.assert_eq[String](":id", params(1)?)
      h.assert_eq[String]("*rest", params(3)?)
    else
      h.fail("param/wildcard segment access failed")
    end

class \nodoc\ iso _PropertySplitJoinRoundTrip is Property1[String]
  """

  Splitting a static path into segments and joining them all back produces
  the original path without the leading slash.
  """

  fun name(): String => "router/property/split join round-trip"

  fun gen(): Generator[String] => _GenStaticPath()

  fun property(path: String, h: PropertyHelper) =>
    let segments = _SplitSegments(path)
    let rejoined = _JoinRemainingSegments(segments, 0)
    // _SplitSegments strips the leading '/'; _JoinRemainingSegments
    // does not add it back. So "/" + rejoined == path.
    h.assert_eq[String](path, "/" + rejoined)

class \nodoc\ iso _TestJoinRemainingSegments is UnitTest
  """

  `_JoinRemainingSegments` edge cases: past-end index, single segment,
  multiple segments, and mid-array start.
  """

  fun name(): String => "router/join remaining segments"

  fun apply(h: TestHelper) =>
    let segments: Array[String] val =
      recover val ["api"; "v1"; "users"; "42"] end

    // from >= size → empty string
    h.assert_eq[String](
      "",
      _JoinRemainingSegments(segments, 10),
      "past-end should return empty")
    h.assert_eq[String](
      "",
      _JoinRemainingSegments(segments, 4),
      "at-size should return empty")

    // Empty array → empty string
    let empty: Array[String] val =
      recover val Array[String] end
    h.assert_eq[String](
      "",
      _JoinRemainingSegments(empty, 0),
      "empty array should return empty")

    // Single remaining segment (fast path)
    h.assert_eq[String](
      "42",
      _JoinRemainingSegments(segments, 3),
      "single remaining should return that segment")

    // Multiple remaining segments
    h.assert_eq[String](
      "v1/users/42",
      _JoinRemainingSegments(segments, 1),
      "join from index 1")

    // All segments from start
    h.assert_eq[String](
      "api/v1/users/42",
      _JoinRemainingSegments(segments, 0),
      "join all segments")

class \nodoc\ iso _TestRoutesBeforeInterceptors is UnitTest
  """

  Routes registered before interceptors still get the interceptors.

  `add_interceptors` may be called after `add` — the tree traversal in
  `_ensure_path` must work on a tree that already has route nodes.
  """

  fun name(): String => "router/routes before interceptors"

  fun apply(h: TestHelper) =>
    let interceptor: RequestInterceptor val = _PassInterceptor
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: interceptor] end
    let builder = _RouterBuilder
    // Routes first
    builder.add(stallion.GET, "/api/users", _NoOpFactory, None)
    builder.add(stallion.GET, "/api/items", _NoOpFactory, None)
    // Interceptors after
    builder.add_interceptors("/api", interceptors, None)
    let router = builder.build()

    // Both routes should have the interceptor
    match router.lookup(stallion.GET, "/api/users")
    | let m: _RouteMatch =>
      match m.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(ints(0)? is interceptor)
        else
          h.fail("interceptor access failed")
        end
      else
        h.fail("/api/users should have interceptors")
      end
    else
      h.fail("expected match for /api/users")
    end

    match router.lookup(stallion.GET, "/api/items")
    | let m: _RouteMatch =>
      match m.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(ints(0)? is interceptor)
        else
          h.fail("interceptor access failed")
        end
      else
        h.fail("/api/items should have interceptors")
      end
    else
      h.fail("expected match for /api/items")
    end

    // Miss under /api should also carry interceptors
    match router.lookup(stallion.GET, "/api/nonexistent")
    | let miss: _RouteMiss =>
      match miss.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(ints(0)? is interceptor)
        else
          h.fail("interceptor access failed")
        end
      else
        h.fail("miss should carry interceptors")
      end
    else
      h.fail("expected miss for /api/nonexistent")
    end

class \nodoc\ iso _TestMethodNotAllowedCarriesInterceptors is UnitTest
  """
  405 responses carry accumulated interceptors from the matched path.
  """
  fun name(): String => "router/method not allowed carries interceptors"

  fun apply(h: TestHelper) =>
    let interceptor: RequestInterceptor val = _PassInterceptor
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: interceptor] end
    let resp_interceptor: ResponseInterceptor val = _NoOpResponseInterceptor
    let resp_interceptors: Array[ResponseInterceptor val] val =
      recover val [as ResponseInterceptor val: resp_interceptor] end

    let builder = _RouterBuilder
    builder.add_interceptors("/api", interceptors, resp_interceptors)
    builder.add(stallion.POST, "/api/users", _NoOpFactory, None)
    let router = builder.build()

    // GET to POST-only path → 405 with /api's interceptors
    match \exhaustive\ router.lookup(stallion.GET, "/api/users")
    | let na: _MethodNotAllowed =>
      match na.interceptors
      | let ints: Array[RequestInterceptor val] val =>
        h.assert_eq[USize](1, ints.size())
        try
          h.assert_true(
            ints(0)? is interceptor,
            "405 should carry request "
              + "interceptor from /api")
        else
          h.fail("interceptor access failed")
        end
      else
        h.fail(
          "405 should have request interceptors")
      end
      match na.response_interceptors
      | let ris: Array[ResponseInterceptor val] val =>
        h.assert_eq[USize](1, ris.size())
        try
          h.assert_true(
            ris(0)? is resp_interceptor,
            "405 should carry response "
              + "interceptor from /api")
        else
          h.fail("response interceptor access failed")
        end
      else
        h.fail("405 should have response interceptors")
      end
    | let _: _RouteMatch =>
      h.fail("should not match GET on POST-only route")
    | let _: _RouteMiss =>
      h.fail("should be 405, not 404")
    end
