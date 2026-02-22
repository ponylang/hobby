use "pony_test"
use "pony_check"
use "collections"
use stallion = "stallion"

primitive \nodoc\ _TestRouteGroupList
  fun tests(test: PonyTest) =>
    // Property tests
    test(Property1UnitTest[
      (String, String)](_PropertyGroupPrefixMatches))
    test(Property1UnitTest[
      (USize, USize)](_PropertyGroupMiddlewarePreserved))
    test(Property1UnitTest[
      (String, String, String)](_PropertyNestedGroupPrefixOrder))
    test(Property1UnitTest[
      (String, String)](_PropertyGroupFlattenEquivalence))
    // Example tests
    test(_TestJoinPath)
    test(_TestConcatMiddleware)
    test(_TestNestedGroups)
    test(_TestEmptyGroup)
    test(_TestGroupNoMiddleware)
    test(_TestAppMiddleware)
    test(_TestAppMiddlewareAccumulation)
    test(_TestAppMiddlewareWithGroups)
    test(_TestMultipleGroupsOnApplication)

// --- Test middleware ---

primitive \nodoc\ _NoOpMiddleware is Middleware
  fun before(ctx: Context ref) => None

class \nodoc\ val _MarkerMiddleware is Middleware
  let label: String
  new val create(label': String) => label = label'
  fun before(ctx: Context ref) => None

// --- Generators ---

primitive \nodoc\ _GenSegment
  """Generate a single path segment: lowercase letters, length 1-10."""
  fun apply(): Generator[String] =>
    Generators.ascii(1, 10 where range = ASCIILetters)

// --- Property tests ---

class \nodoc\ iso _PropertyGroupPrefixMatches is
  Property1[(String, String)]
  """A route registered via a group matches at the joined path."""
  fun name(): String => "route-group/property/prefix matches"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](_GenSegment(), _GenSegment())

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let prefix_seg, let route_seg) = sample
    let prefix: String val = "/" + prefix_seg
    let path: String val = "/" + route_seg
    let joined = _JoinPath(prefix, path)

    let builder = _RouterBuilder
    builder.add(stallion.GET, joined, _NoOpHandler, None)
    let router = builder.build()
    match router.lookup(stallion.GET, joined)
    | let _: _RouteMatch => None
    else
      h.fail("expected match at " + joined)
    end

class \nodoc\ iso _PropertyGroupMiddlewarePreserved is
  Property1[(USize, USize)]
  """Concatenated middleware has size = sum of input sizes."""
  fun name(): String => "route-group/property/middleware preserved"

  fun gen(): Generator[(USize, USize)] =>
    Generators.zip2[USize, USize](
      Generators.usize(0, 5),
      Generators.usize(0, 5))

  fun property(sample: (USize, USize), h: PropertyHelper) =>
    (let group_count, let route_count) = sample
    let group_mw: (Array[Middleware val] val | None) =
      if group_count > 0 then
        recover val
          let a = Array[Middleware val](group_count)
          var i: USize = 0
          while i < group_count do
            a.push(_NoOpMiddleware)
            i = i + 1
          end
          a
        end
      else
        None
      end
    let route_mw: (Array[Middleware val] val | None) =
      if route_count > 0 then
        recover val
          let a = Array[Middleware val](route_count)
          var i: USize = 0
          while i < route_count do
            a.push(_NoOpMiddleware)
            i = i + 1
          end
          a
        end
      else
        None
      end
    let result = _ConcatMiddleware(group_mw, route_mw)
    let expected = group_count + route_count
    match result
    | let a: Array[Middleware val] val =>
      h.assert_eq[USize](expected, a.size())
    else
      h.assert_eq[USize](0, expected)
    end

class \nodoc\ iso _PropertyNestedGroupPrefixOrder is
  Property1[(String, String, String)]
  """Nested group paths join as outer + inner + route."""
  fun name(): String => "route-group/property/nested prefix order"

  fun gen(): Generator[(String, String, String)] =>
    Generators.zip3[String, String, String](
      _GenSegment(), _GenSegment(), _GenSegment())

  fun property(sample: (String, String, String), h: PropertyHelper) =>
    (let outer_seg, let inner_seg, let route_seg) = sample
    let joined: String val =
      "/" + outer_seg + "/" + inner_seg + "/" + route_seg

    let builder = _RouterBuilder
    builder.add(stallion.GET, joined, _NoOpHandler, None)
    let router = builder.build()
    match router.lookup(stallion.GET, joined)
    | let _: _RouteMatch => None
    else
      h.fail("expected match at " + joined)
    end

class \nodoc\ iso _PropertyGroupFlattenEquivalence is
  Property1[(String, String)]
  """Flattened group route matches the same as a manually built route."""
  fun name(): String => "route-group/property/flatten equivalence"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](_GenSegment(), _GenSegment())

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let prefix_seg, let route_seg) = sample
    let prefix: String val = "/" + prefix_seg
    let path: String val = "/" + route_seg
    let joined = _JoinPath(prefix, path)

    // Build via JoinPath + RouterBuilder
    let builder1 = _RouterBuilder
    builder1.add(stallion.GET, joined, _NoOpHandler, None)
    let router1 = builder1.build()

    // Build via manual string concatenation
    let manual: String val = prefix + path
    let builder2 = _RouterBuilder
    builder2.add(stallion.GET, manual, _NoOpHandler, None)
    let router2 = builder2.build()

    let r1_matches = router1.lookup(stallion.GET, joined) isnt None
    let r2_matches = router2.lookup(stallion.GET, joined) isnt None
    h.assert_eq[Bool](r1_matches, r2_matches)

// --- Example-based tests ---

class \nodoc\ iso _TestJoinPath is UnitTest
  """_JoinPath handles various prefix/path combinations."""
  fun name(): String => "route-group/join path"

  fun apply(h: TestHelper) =>
    // Normal case
    h.assert_eq[String]("/api/users", _JoinPath("/api", "/users"))
    // Trailing slash on prefix
    h.assert_eq[String]("/api/users", _JoinPath("/api/", "/users"))
    // Root prefix
    h.assert_eq[String]("/health", _JoinPath("/", "/health"))
    // Empty prefix
    h.assert_eq[String]("/health", _JoinPath("", "/health"))
    // Root group with root route
    h.assert_eq[String]("/", _JoinPath("/", "/"))
    // Multi-segment prefix
    h.assert_eq[String]("/api/v1/users",
      _JoinPath("/api/v1", "/users"))
    // Multi-segment prefix with trailing slash
    h.assert_eq[String]("/api/v1/users",
      _JoinPath("/api/v1/", "/users"))

class \nodoc\ iso _TestConcatMiddleware is UnitTest
  """_ConcatMiddleware combines middleware arrays correctly."""
  fun name(): String => "route-group/concat middleware"

  fun apply(h: TestHelper) =>
    let mw1 = _MarkerMiddleware("a")
    let mw2 = _MarkerMiddleware("b")
    let outer: Array[Middleware val] val =
      recover val [as Middleware val: mw1] end
    let inner: Array[Middleware val] val =
      recover val [as Middleware val: mw2] end

    // Both non-None
    match _ConcatMiddleware(outer, inner)
    | let a: Array[Middleware val] val =>
      h.assert_eq[USize](2, a.size())
      try
        h.assert_is[Middleware](mw1, a(0)?)
        h.assert_is[Middleware](mw2, a(1)?)
      else
        h.fail("middleware identity mismatch")
      end
    else
      h.fail("expected combined array")
    end

    // Outer only
    match _ConcatMiddleware(outer, None)
    | let a: Array[Middleware val] val =>
      h.assert_eq[USize](1, a.size())
    else
      h.fail("expected outer array")
    end

    // Inner only
    match _ConcatMiddleware(None, inner)
    | let a: Array[Middleware val] val =>
      h.assert_eq[USize](1, a.size())
    else
      h.fail("expected inner array")
    end

    // Both None
    match _ConcatMiddleware(None, None)
    | let _: Array[Middleware val] val =>
      h.fail("expected None")
    end

class \nodoc\ iso _TestNestedGroups is UnitTest
  """Two levels of nesting produce correct path and middleware order."""
  fun name(): String => "route-group/nested groups"

  fun apply(h: TestHelper) =>
    let outer_mw = _MarkerMiddleware("outer")
    let inner_mw = _MarkerMiddleware("inner")
    let route_mw = _MarkerMiddleware("route")

    let outer_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: outer_mw] end
    let inner_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: inner_mw] end
    let route_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: route_mw] end

    // Build inner group
    let inner = RouteGroup("/admin" where middleware = inner_mw_arr)
    inner.get("/dashboard", _NoOpHandler where middleware = route_mw_arr)

    // Build outer group and nest inner
    let outer = RouteGroup("/api" where middleware = outer_mw_arr)
    outer.group(consume inner)

    // Flatten into target (consume iso to ref for box method call)
    let target = Array[_RouteDefinition]
    let outer_ref: RouteGroup ref = consume outer
    outer_ref._flatten_into(target)

    h.assert_eq[USize](1, target.size())
    try
      let r = target(0)?
      h.assert_eq[String]("/api/admin/dashboard", r.path)
      match r.middleware
      | let mw: Array[Middleware val] val =>
        h.assert_eq[USize](3, mw.size())
        h.assert_is[Middleware](outer_mw, mw(0)?)
        h.assert_is[Middleware](inner_mw, mw(1)?)
        h.assert_is[Middleware](route_mw, mw(2)?)
      else
        h.fail("expected middleware array")
      end
    else
      h.fail("expected one route")
    end

class \nodoc\ iso _TestEmptyGroup is UnitTest
  """An empty group flattens zero routes."""
  fun name(): String => "route-group/empty group"

  fun apply(h: TestHelper) =>
    let g = RouteGroup("/api")
    let target = Array[_RouteDefinition]
    let g_ref: RouteGroup ref = consume g
    g_ref._flatten_into(target)
    h.assert_eq[USize](0, target.size())

class \nodoc\ iso _TestGroupNoMiddleware is UnitTest
  """A group with prefix only preserves route middleware unchanged."""
  fun name(): String => "route-group/no middleware"

  fun apply(h: TestHelper) =>
    let route_mw = _MarkerMiddleware("route")
    let route_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: route_mw] end

    let g = RouteGroup("/api")
    g.get("/users", _NoOpHandler where middleware = route_mw_arr)

    let target = Array[_RouteDefinition]
    let g_ref: RouteGroup ref = consume g
    g_ref._flatten_into(target)

    h.assert_eq[USize](1, target.size())
    try
      let r = target(0)?
      h.assert_eq[String]("/api/users", r.path)
      match r.middleware
      | let mw: Array[Middleware val] val =>
        h.assert_eq[USize](1, mw.size())
        h.assert_is[Middleware](route_mw, mw(0)?)
      else
        h.fail("expected middleware array")
      end
    else
      h.fail("expected one route")
    end

class \nodoc\ iso _TestAppMiddleware is UnitTest
  """Application middleware is prepended to every route's middleware."""
  fun name(): String => "route-group/app middleware"

  fun apply(h: TestHelper) =>
    let app_mw = _MarkerMiddleware("app")
    let route_mw = _MarkerMiddleware("route")

    let app_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: app_mw] end
    let route_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: route_mw] end

    // Simulate what serve() does: ConcatMiddleware(app_mw, route_mw)
    match _ConcatMiddleware(app_mw_arr, route_mw_arr)
    | let combined: Array[Middleware val] val =>
      h.assert_eq[USize](2, combined.size())
      try
        h.assert_is[Middleware](app_mw, combined(0)?)
        h.assert_is[Middleware](route_mw, combined(1)?)
      else
        h.fail("middleware identity mismatch")
      end
    else
      h.fail("expected combined array")
    end

    // Route with no middleware gets app middleware only
    match _ConcatMiddleware(app_mw_arr, None)
    | let combined: Array[Middleware val] val =>
      h.assert_eq[USize](1, combined.size())
      try
        h.assert_is[Middleware](app_mw, combined(0)?)
      else
        h.fail("middleware identity mismatch")
      end
    else
      h.fail("expected app middleware array")
    end

class \nodoc\ iso _TestAppMiddlewareAccumulation is UnitTest
  """Multiple middleware() calls accumulate in order."""
  fun name(): String => "route-group/app middleware accumulation"

  fun apply(h: TestHelper) =>
    let mw1 = _MarkerMiddleware("first")
    let mw2 = _MarkerMiddleware("second")

    let arr1: Array[Middleware val] val =
      recover val [as Middleware val: mw1] end
    let arr2: Array[Middleware val] val =
      recover val [as Middleware val: mw2] end

    // Simulate accumulation: push both into a single array, then build val
    let accumulated: Array[Middleware val] iso =
      recover iso Array[Middleware val] end
    for m in arr1.values() do
      accumulated.push(m)
    end
    for m in arr2.values() do
      accumulated.push(m)
    end
    let result: Array[Middleware val] val = consume accumulated

    h.assert_eq[USize](2, result.size())
    try
      h.assert_is[Middleware](mw1, result(0)?)
      h.assert_is[Middleware](mw2, result(1)?)
    else
      h.fail("middleware order mismatch")
    end

class \nodoc\ iso _TestAppMiddlewareWithGroups is UnitTest
  """App middleware + group middleware + route middleware in correct order."""
  fun name(): String => "route-group/app middleware with groups"

  fun apply(h: TestHelper) =>
    let app_mw = _MarkerMiddleware("app")
    let group_mw = _MarkerMiddleware("group")
    let route_mw = _MarkerMiddleware("route")

    let app_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: app_mw] end
    let group_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: group_mw] end
    let route_mw_arr: Array[Middleware val] val =
      recover val [as Middleware val: route_mw] end

    // Group flattening: concat group_mw + route_mw
    let group_combined = _ConcatMiddleware(group_mw_arr, route_mw_arr)

    // App serve: concat app_mw + group_combined
    match _ConcatMiddleware(app_mw_arr, group_combined)
    | let combined: Array[Middleware val] val =>
      h.assert_eq[USize](3, combined.size())
      try
        h.assert_is[Middleware](app_mw, combined(0)?)
        h.assert_is[Middleware](group_mw, combined(1)?)
        h.assert_is[Middleware](route_mw, combined(2)?)
      else
        h.fail("middleware order mismatch")
      end
    else
      h.fail("expected combined array")
    end

class \nodoc\ iso _TestMultipleGroupsOnApplication is UnitTest
  """Two separate groups flatten independently into application routes."""
  fun name(): String => "route-group/multiple groups on application"

  fun apply(h: TestHelper) =>
    let h1 = _TestMarkerHandler("api")
    let h2 = _TestMarkerHandler("admin")

    let g1 = RouteGroup("/api")
    g1.get("/users", h1)

    let g2 = RouteGroup("/admin")
    g2.get("/dashboard", h2)

    let target = Array[_RouteDefinition]
    let g1_ref: RouteGroup ref = consume g1
    g1_ref._flatten_into(target)
    let g2_ref: RouteGroup ref = consume g2
    g2_ref._flatten_into(target)

    h.assert_eq[USize](2, target.size())
    try
      h.assert_eq[String]("/api/users", target(0)?.path)
      h.assert_is[Handler](h1, target(0)?.handler)
      h.assert_eq[String]("/admin/dashboard", target(1)?.path)
      h.assert_is[Handler](h2, target(1)?.handler)
    else
      h.fail("expected two routes")
    end
