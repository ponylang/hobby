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
      (String, String, String)](_PropertyNestedGroupPrefixOrder))
    test(Property1UnitTest[
      (String, String)](_PropertyGroupFlattenEquivalence))
    // Example tests
    test(_TestJoinPath)
    test(_TestEmptyGroup)
    test(_TestMultipleGroupsOnApplication)

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
    builder.add(stallion.GET, joined, _NoOpFactory, None)
    let router = builder.build()
    match router.lookup(stallion.GET, joined)
    | let _: _RouteMatch => None
    else
      h.fail("expected match at " + joined)
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
    builder.add(stallion.GET, joined, _NoOpFactory, None)
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
    builder1.add(stallion.GET, joined, _NoOpFactory, None)
    let router1 = builder1.build()

    // Build via manual string concatenation
    let manual: String val = prefix + path
    let builder2 = _RouterBuilder
    builder2.add(stallion.GET, manual, _NoOpFactory, None)
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

class \nodoc\ iso _TestEmptyGroup is UnitTest
  """An empty group flattens zero routes."""
  fun name(): String => "route-group/empty group"

  fun apply(h: TestHelper) =>
    let g = RouteGroup("/api")
    let target = Array[_RouteDefinition]
    let g_ref: RouteGroup ref = consume g
    g_ref._flatten_into(target)
    h.assert_eq[USize](0, target.size())

class \nodoc\ iso _TestMultipleGroupsOnApplication is UnitTest
  """Two separate groups flatten independently into application routes."""
  fun name(): String => "route-group/multiple groups on application"

  fun apply(h: TestHelper) =>
    let f1: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "api")
    } val
    let f2: HandlerFactory = {(ctx) =>
      RequestHandler(consume ctx).respond(stallion.StatusOK, "admin")
    } val

    let g1 = RouteGroup("/api")
    g1.get("/users", f1)

    let g2 = RouteGroup("/admin")
    g2.get("/dashboard", f2)

    let target = Array[_RouteDefinition]
    let g1_ref: RouteGroup ref = consume g1
    g1_ref._flatten_into(target)
    let g2_ref: RouteGroup ref = consume g2
    g2_ref._flatten_into(target)

    h.assert_eq[USize](2, target.size())
    try
      h.assert_eq[String]("/api/users", target(0)?.path)
      h.assert_is[HandlerFactory](f1, target(0)?.factory)
      h.assert_eq[String]("/admin/dashboard", target(1)?.path)
      h.assert_is[HandlerFactory](f2, target(1)?.factory)
    else
      h.fail("expected two routes")
    end
