use "constrained_types"
use "pony_test"
use stallion = "stallion"

primitive \nodoc\ _TestBuildList
  fun tests(test: PonyTest) =>
    test(_TestBuildValidConfig)
    test(_TestBuildInvalidConfig)
    test(_TestBuildIncremental)
    test(_TestHandlerTimeoutZeroRejects)
    test(_TestHandlerTimeoutValidAccepts)
    test(_TestHandlerTimeoutOverflowRejects)
    test(_TestDefaultHandlerTimeout)
    test(_TestMakeHandlerTimeoutBoundary)
    test(_TestHandlerTimeoutToNsNone)

// --- Application.build() tests ---
class \nodoc\ iso _TestBuildValidConfig is UnitTest
  """
  Application.build() returns BuiltApplication on valid config.
  """
  fun name(): String => "build/valid config"

  fun apply(h: TestHelper) =>
    let app = Application
    app.get(
      "/",
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "ok")
      } val)
    match \exhaustive\ app.build()
    | let _: BuiltApplication => h.assert_true(true)
    | let err: ConfigError =>
      h.fail("expected BuiltApplication, got: "
        + err.message)
    end

class \nodoc\ iso _TestBuildInvalidConfig is UnitTest
  """
  Application.build() returns ConfigError on invalid config.
  """
  fun name(): String => "build/invalid config"

  fun apply(h: TestHelper) =>
    let app = Application
    // Overlapping group prefixes
    let g1 =
      RouteGroup(
        "/api"
        where interceptors =
          recover val
            [ as RequestInterceptor val:
              _BuildTestPassInterceptor]
          end)
    g1.get(
      "/a",
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "ok")
      } val)
    let g2 =
      RouteGroup(
        "/api"
        where interceptors =
          recover val
            [ as RequestInterceptor val:
              _BuildTestPassInterceptor]
          end)
    g2.get(
      "/b",
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "ok")
      } val)
    app.group(consume g1)
    app.group(consume g2)
    match \exhaustive\ app.build()
    | let _: BuiltApplication =>
      h.fail("expected ConfigError")
    | let _: ConfigError =>
      h.assert_true(true)
    end

class \nodoc\ iso _TestBuildIncremental is UnitTest
  """
  Multiple builds from the same Application produce independent
  snapshots.
  """
  fun name(): String => "build/incremental"

  fun apply(h: TestHelper) =>
    let app = Application
    app.get(
      "/a",
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "ok")
      } val)
    // First build: only /a
    let built1 =
      match \exhaustive\ app.build()
      | let b: BuiltApplication => b
      | let err: ConfigError =>
        h.fail(
          "first build failed: " + err.message)
        return
      end

    app.get(
      "/b",
      {(ctx) =>
        RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "ok")
      } val)
    // Second build: /a and /b
    let built2 =
      match \exhaustive\ app.build()
      | let b: BuiltApplication => b
      | let err: ConfigError =>
        h.fail(
          "second build failed: " + err.message)
        return
      end

    // First build should miss /b
    let r1 = built1._get_router()
    match r1.lookup(stallion.GET, "/b")
    | let _: _RouteMiss => h.assert_true(true)
    else
      h.fail("/b should miss in first build")
    end

    // Second build should match both /a and /b
    let r2 = built2._get_router()
    match r2.lookup(stallion.GET, "/a")
    | let _: _RouteMatch => None
    else
      h.fail("/a should match in second build")
    end
    match r2.lookup(stallion.GET, "/b")
    | let _: _RouteMatch => h.assert_true(true)
    else
      h.fail("/b should match in second build")
    end

// --- HandlerTimeout tests ---
class \nodoc\ iso _TestHandlerTimeoutZeroRejects is UnitTest
  """
  MakeHandlerTimeout(0) returns ValidationFailure.
  """
  fun name(): String => "handler timeout/zero rejects"

  fun apply(h: TestHelper) =>
    match \exhaustive\ MakeHandlerTimeout(0)
    | let _: HandlerTimeout =>
      h.fail("expected ValidationFailure for 0")
    | let _: ValidationFailure =>
      h.assert_true(true)
    end

class \nodoc\ iso _TestHandlerTimeoutValidAccepts is UnitTest
  """
  MakeHandlerTimeout with a valid value succeeds.
  """
  fun name(): String => "handler timeout/valid accepts"

  fun apply(h: TestHelper) =>
    match \exhaustive\ MakeHandlerTimeout(1000)
    | let t: HandlerTimeout =>
      h.assert_eq[U64](1000, t())
    | let _: ValidationFailure =>
      h.fail("expected HandlerTimeout for 1000")
    end

class \nodoc\ iso _TestHandlerTimeoutOverflowRejects is UnitTest
  """
  MakeHandlerTimeout with overflow value returns
  ValidationFailure.
  """
  fun name(): String => "handler timeout/overflow rejects"

  fun apply(h: TestHelper) =>
    // One more than the max safe millisecond value
    let overflow = (U64.max_value() / 1_000_000) + 1
    match \exhaustive\ MakeHandlerTimeout(overflow)
    | let _: HandlerTimeout =>
      h.fail("expected ValidationFailure for overflow")
    | let _: ValidationFailure =>
      h.assert_true(true)
    end

class \nodoc\ iso _TestDefaultHandlerTimeout is UnitTest
  """
  DefaultHandlerTimeout returns a valid HandlerTimeout.
  """
  fun name(): String => "handler timeout/default"

  fun apply(h: TestHelper) =>
    match \exhaustive\ DefaultHandlerTimeout()
    | let t: HandlerTimeout =>
      h.assert_eq[U64](30_000, t())
    | None =>
      h.fail("expected HandlerTimeout, got None")
    end

class \nodoc\ iso _TestMakeHandlerTimeoutBoundary is UnitTest
  """
  MakeHandlerTimeout at the exact maximum value succeeds.
  """
  fun name(): String => "handler timeout/boundary max"

  fun apply(h: TestHelper) =>
    let max_ms = U64.max_value() / 1_000_000
    match \exhaustive\ MakeHandlerTimeout(max_ms)
    | let t: HandlerTimeout =>
      h.assert_eq[U64](max_ms, t())
    | let _: ValidationFailure =>
      h.fail(
        "expected HandlerTimeout for max boundary")
    end

    // Also test minimum boundary (1)
    match \exhaustive\ MakeHandlerTimeout(1)
    | let t: HandlerTimeout =>
      h.assert_eq[U64](1, t())
    | let _: ValidationFailure =>
      h.fail("expected HandlerTimeout for 1")
    end

class \nodoc\ iso _TestHandlerTimeoutToNsNone is UnitTest
  """
  _HandlerTimeoutToNs returns 0 when given None.
  """
  fun name(): String => "handler timeout/to_ns none"

  fun apply(h: TestHelper) =>
    h.assert_eq[U64](
      0, _HandlerTimeoutToNs(None))

// --- Test helpers ---
primitive \nodoc\ _BuildTestPassInterceptor
  is RequestInterceptor
  fun apply(
    request: stallion.Request box)
    : InterceptResult
  =>
    InterceptPass
