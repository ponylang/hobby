use "collections"
use "pony_test"
use "uri"
use stallion = "stallion"
use lori = "lori"

primitive \nodoc\ _TestRequestInterceptorList
  fun tests(test: PonyTest) =>
    test(_TestInterceptRespondSetHeader)
    test(_TestInterceptRespondSetHeaderReplace)
    test(_TestInterceptRespondSetHeaderCaseInsensitive)
    test(_TestInterceptRespondAddHeader)
    test(_TestInterceptRespondAddHeaderMultiple)
    test(_TestRunInterceptorsNone)
    test(_TestRunInterceptorsPass)
    test(_TestRunInterceptorsReject)
    test(_TestRunInterceptorsFirstRejectWins)
    test(_TestConcatInterceptorsNone)
    test(_TestConcatInterceptorsBoth)
    test(_TestConcatInterceptorsOuterOnly)
    test(_TestConcatInterceptorsInnerOnly)
    test(_TestInterceptRespondIntegration)
    test(_TestInterceptPassIntegration)
    test(_TestInterceptGroupIntegration)
    test(_TestAppInterceptIntegration)
    test(_TestInterceptGroup404Integration)
    test(_TestInterceptGroup405Integration)

// --- Test interceptors ---

class \nodoc\ val _RejectInterceptor is RequestInterceptor
  fun apply(request: stallion.Request box): InterceptResult =>
    InterceptRespond(stallion.StatusForbidden, "Forbidden by interceptor")

class \nodoc\ val _RejectWithHeaderInterceptor is RequestInterceptor
  fun apply(request: stallion.Request box): InterceptResult =>
    InterceptRespond(stallion.StatusForbidden, "Forbidden")
      .>set_header("x-interceptor", "rejected")

class \nodoc\ val _PassInterceptor is RequestInterceptor
  fun apply(request: stallion.Request box): InterceptResult =>
    InterceptPass

class \nodoc\ val _AuthHeaderInterceptor is RequestInterceptor
  fun apply(request: stallion.Request box): InterceptResult =>
    match request.headers.get("authorization")
    | let _: String => InterceptPass
    else
      InterceptRespond(stallion.StatusUnauthorized, "Unauthorized")
    end

// --- InterceptRespond unit tests ---

class \nodoc\ iso _TestInterceptRespondSetHeader is UnitTest
  fun name(): String => "interceptor/reject set_header"

  fun apply(h: TestHelper) =>
    let r = InterceptRespond(stallion.StatusForbidden, "no")
    r.set_header("X-Custom", "value")
    h.assert_eq[USize](1, r._headers_size())
    try
      (let n, let v) = r._header_at(0)?
      h.assert_eq[String]("x-custom", n)
      h.assert_eq[String]("value", v)
    else
      h.fail("header not found")
    end

class \nodoc\ iso _TestInterceptRespondSetHeaderReplace is UnitTest
  fun name(): String => "interceptor/reject set_header replace"

  fun apply(h: TestHelper) =>
    let r = InterceptRespond(stallion.StatusForbidden, "no")
    r.set_header("x-custom", "old")
    r.set_header("x-custom", "new")
    h.assert_eq[USize](1, r._headers_size())
    try
      (_, let v) = r._header_at(0)?
      h.assert_eq[String]("new", v)
    else
      h.fail("header not found")
    end

class \nodoc\ iso _TestInterceptRespondSetHeaderCaseInsensitive is UnitTest
  fun name(): String => "interceptor/reject set_header case insensitive"

  fun apply(h: TestHelper) =>
    let r = InterceptRespond(stallion.StatusForbidden, "no")
    r.set_header("X-Custom", "old")
    r.set_header("x-custom", "new")
    h.assert_eq[USize](1, r._headers_size())
    try
      (_, let v) = r._header_at(0)?
      h.assert_eq[String]("new", v)
    else
      h.fail("header not found")
    end

class \nodoc\ iso _TestInterceptRespondAddHeader is UnitTest
  fun name(): String => "interceptor/reject add_header"

  fun apply(h: TestHelper) =>
    let r = InterceptRespond(stallion.StatusForbidden, "no")
    r.add_header("Set-Cookie", "a=1")
    h.assert_eq[USize](1, r._headers_size())
    try
      (let n, let v) = r._header_at(0)?
      h.assert_eq[String]("set-cookie", n)
      h.assert_eq[String]("a=1", v)
    else
      h.fail("header not found")
    end

class \nodoc\ iso _TestInterceptRespondAddHeaderMultiple is UnitTest
  fun name(): String => "interceptor/reject add_header multiple"

  fun apply(h: TestHelper) =>
    let r = InterceptRespond(stallion.StatusForbidden, "no")
    r.add_header("Set-Cookie", "a=1")
    r.add_header("Set-Cookie", "b=2")
    h.assert_eq[USize](2, r._headers_size())

// --- _RunRequestInterceptors unit tests ---

class \nodoc\ iso _TestRunInterceptorsNone is UnitTest
  fun name(): String => "interceptor/run interceptors none"

  fun apply(h: TestHelper) =>
    let request = _InterceptorTestRequest()
    h.assert_true(_RunRequestInterceptors(request, None) is None)

class \nodoc\ iso _TestRunInterceptorsPass is UnitTest
  fun name(): String => "interceptor/run interceptors pass"

  fun apply(h: TestHelper) =>
    let request = _InterceptorTestRequest()
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end
    h.assert_true(_RunRequestInterceptors(request, interceptors) is None)

class \nodoc\ iso _TestRunInterceptorsReject is UnitTest
  fun name(): String => "interceptor/run interceptors reject"

  fun apply(h: TestHelper) =>
    let request = _InterceptorTestRequest()
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    match _RunRequestInterceptors(request, interceptors)
    | let r: InterceptRespond =>
      h.assert_true(r._response_status() is stallion.StatusForbidden)
    else
      h.fail("expected rejection")
    end

class \nodoc\ iso _TestRunInterceptorsFirstRejectWins is UnitTest
  fun name(): String => "interceptor/run interceptors first reject wins"

  fun apply(h: TestHelper) =>
    let request = _InterceptorTestRequest()
    let interceptors: Array[RequestInterceptor val] val =
      recover val
        [as RequestInterceptor val: _PassInterceptor; _RejectInterceptor; _PassInterceptor]
      end
    match _RunRequestInterceptors(request, interceptors)
    | let r: InterceptRespond =>
      h.assert_true(r._response_status() is stallion.StatusForbidden)
    else
      h.fail("expected rejection")
    end

// --- _ConcatInterceptors unit tests ---

class \nodoc\ iso _TestConcatInterceptorsNone is UnitTest
  fun name(): String => "interceptor/concat interceptors none"

  fun apply(h: TestHelper) =>
    h.assert_true(_ConcatInterceptors(None, None) is None)

class \nodoc\ iso _TestConcatInterceptorsBoth is UnitTest
  fun name(): String => "interceptor/concat interceptors both"

  fun apply(h: TestHelper) =>
    let outer: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end
    let inner: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    match _ConcatInterceptors(outer, inner)
    | let combined: Array[RequestInterceptor val] val =>
      h.assert_eq[USize](2, combined.size())
    else
      h.fail("expected combined array")
    end

class \nodoc\ iso _TestConcatInterceptorsOuterOnly is UnitTest
  fun name(): String => "interceptor/concat interceptors outer only"

  fun apply(h: TestHelper) =>
    let outer: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end
    match _ConcatInterceptors(outer, None)
    | let result: Array[RequestInterceptor val] val =>
      h.assert_eq[USize](1, result.size())
    else
      h.fail("expected array")
    end

class \nodoc\ iso _TestConcatInterceptorsInnerOnly is UnitTest
  fun name(): String => "interceptor/concat interceptors inner only"

  fun apply(h: TestHelper) =>
    let inner: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    match _ConcatInterceptors(None, inner)
    | let result: Array[RequestInterceptor val] val =>
      h.assert_eq[USize](1, result.size())
    else
      h.fail("expected array")
    end

// --- Integration tests ---

class \nodoc\ iso _TestInterceptRespondIntegration is UnitTest
  fun name(): String => "integration/interceptor reject"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory)]
    end where interceptors' = interceptors)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Forbidden by interceptor")

class \nodoc\ iso _TestInterceptPassIntegration is UnitTest
  fun name(): String => "integration/interceptor pass"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _PassInterceptor] end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory)]
    end where interceptors' = interceptors)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello from Hobby!")

class \nodoc\ iso _TestInterceptGroupIntegration is UnitTest
  """Interceptors on a route group reject before the handler runs."""
  fun name(): String => "integration/interceptor route group"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/api/users", _HelloFactory, None, interceptors)
    let router = builder.build()
    _IntegrationHelpers.run_test(h, router,
      "GET /api/users HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Forbidden by interceptor")

class \nodoc\ iso _TestAppInterceptIntegration is UnitTest
  fun name(): String => "integration/app-level interceptor"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory)]
    end where interceptors' = interceptors)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Forbidden by interceptor")

class \nodoc\ iso _TestInterceptGroup404Integration is UnitTest
  """Group request interceptor fires on 404 under the group's prefix."""
  fun name(): String => "integration/interceptor group 404"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    let builder = _RouterBuilder
    builder.add_interceptors("/api", interceptors, None)
    builder.add(stallion.GET, "/api/users", _HelloFactory)
    let router = builder.build()
    // Request to /api/nonexistent should hit the /api group's interceptor
    // and get rejected with 403 instead of 404
    _IntegrationHelpers.run_test(h, router,
      "GET /api/nonexistent HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Forbidden by interceptor")

class \nodoc\ iso _TestInterceptGroup405Integration is UnitTest
  """Group request interceptor fires on 405 under the group's prefix."""
  fun name(): String => "integration/interceptor group 405"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    let builder = _RouterBuilder
    builder.add_interceptors("/api", interceptors, None)
    builder.add(stallion.POST, "/api/users", _HelloFactory)
    let router = builder.build()
    // GET to POST-only /api/users should hit the /api group's interceptor
    // and get rejected with 403 instead of 405
    _IntegrationHelpers.run_test(h, router,
      "GET /api/users HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Forbidden by interceptor")

// --- Helpers ---

primitive \nodoc\ _InterceptorTestRequest
  fun apply(): stallion.Request val =>
    let mock_uri = URI(None, None, "/", None, None)
    let mock_headers: stallion.Headers val =
      recover val stallion.Headers end
    let mock_cookies = stallion.ParseCookies("")
    stallion.Request(stallion.GET, mock_uri, stallion.HTTP11,
      mock_headers, mock_cookies)
