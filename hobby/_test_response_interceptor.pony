use "collections"
use "pony_test"
use "time"
use "uri"
use stallion = "stallion"
use lori = "lori"

primitive \nodoc\ _TestResponseInterceptorList
  fun tests(test: PonyTest) =>
    // ResponseContext unit tests
    test(_TestResponseContextSetHeader)
    test(_TestResponseContextAddHeader)
    test(_TestResponseContextSetStatus)
    test(_TestResponseContextSetBody)
    test(_TestResponseContextStreamingNoOps)
    // _RunResponseInterceptors unit tests
    test(_TestRunResponseInterceptorsNone)
    test(_TestRunResponseInterceptorsSingle)
    test(_TestRunResponseInterceptorsMultiple)
    // _ConcatResponseInterceptors unit tests
    test(_TestConcatResponseInterceptorsNone)
    test(_TestConcatResponseInterceptorsBoth)
    test(_TestConcatResponseInterceptorsOuterOnly)
    test(_TestConcatResponseInterceptorsInnerOnly)
    // Integration tests
    test(_TestResponseInterceptorSetHeaderIntegration)
    test(_TestResponseInterceptorOn404)
    test(_TestResponseInterceptorOnRejectIntercept)
    test(_TestResponseInterceptorSetBodyIntegration)
    test(_TestResponseInterceptorStreamingIntegration)
    test(_TestResponseInterceptorGroupOn404)

// --- Test interceptors ---

class \nodoc\ val _AddHeaderResponseInterceptor is ResponseInterceptor
  let _name: String
  let _value: String
  new val create(name': String, value': String) =>
    _name = name'
    _value = value'
  fun apply(ctx: ResponseContext ref) =>
    ctx.set_header(_name, _value)

class \nodoc\ val _SetBodyResponseInterceptor is ResponseInterceptor
  let _body: String
  new val create(body': String) => _body = body'
  fun apply(ctx: ResponseContext ref) =>
    ctx.set_body(_body)

class \nodoc\ val _SetStatusResponseInterceptor is ResponseInterceptor
  let _status: stallion.Status
  new val create(status': stallion.Status) => _status = status'
  fun apply(ctx: ResponseContext ref) =>
    ctx.set_status(_status)

class \nodoc\ val _NoOpResponseInterceptor is ResponseInterceptor
  fun apply(ctx: ResponseContext ref) => None

// --- Helper ---

primitive \nodoc\ _ResponseInterceptorTestRequest
  fun apply(): stallion.Request val =>
    let mock_uri = URI(None, None, "/", None, None)
    let mock_headers: stallion.Headers val =
      recover val stallion.Headers end
    let mock_cookies = stallion.ParseCookies("")
    stallion.Request(stallion.GET, mock_uri, stallion.HTTP11,
      mock_headers, mock_cookies)

// --- ResponseContext unit tests ---

class \nodoc\ iso _TestResponseContextSetHeader is UnitTest
  fun name(): String => "response interceptor/set_header case insensitive"

  fun apply(h: TestHelper) =>
    let buf = _BufferedResponse._standard(stallion.StatusOK, "body", false)
    buf.headers.push(("X-Custom", "old-value"))
    let ctx = ResponseContext._create(buf, _ResponseInterceptorTestRequest())
    ctx.set_header("x-custom", "new-value")
    var found_old = false
    var found_new = false
    for (n, v) in buf.headers.values() do
      if n == "X-Custom" then found_old = true end
      if (n == "x-custom") and (v == "new-value") then found_new = true end
    end
    h.assert_false(found_old, "old header should be removed")
    h.assert_true(found_new, "new header should be present")

class \nodoc\ iso _TestResponseContextAddHeader is UnitTest
  fun name(): String => "response interceptor/add_header multiple"

  fun apply(h: TestHelper) =>
    let buf = _BufferedResponse._standard(stallion.StatusOK, "body", false)
    let ctx = ResponseContext._create(buf, _ResponseInterceptorTestRequest())
    ctx.add_header("Set-Cookie", "a=1")
    ctx.add_header("Set-Cookie", "b=2")
    var count: USize = 0
    for (n, _) in buf.headers.values() do
      if n == "set-cookie" then count = count + 1 end
    end
    h.assert_eq[USize](2, count)

class \nodoc\ iso _TestResponseContextSetStatus is UnitTest
  fun name(): String => "response interceptor/set_status"

  fun apply(h: TestHelper) =>
    let buf = _BufferedResponse._standard(stallion.StatusOK, "body", false)
    let ctx = ResponseContext._create(buf, _ResponseInterceptorTestRequest())
    h.assert_true(ctx.status() is stallion.StatusOK)
    ctx.set_status(stallion.StatusNotFound)
    h.assert_true(ctx.status() is stallion.StatusNotFound)

class \nodoc\ iso _TestResponseContextSetBody is UnitTest
  fun name(): String => "response interceptor/set_body"

  fun apply(h: TestHelper) =>
    let buf = _BufferedResponse._standard(stallion.StatusOK, "original", false)
    let ctx = ResponseContext._create(buf, _ResponseInterceptorTestRequest())
    match ctx.body()
    | let s: String val => h.assert_eq[String]("original", s)
    else
      h.fail("expected string body")
    end
    ctx.set_body("replaced")
    match ctx.body()
    | let s: String val => h.assert_eq[String]("replaced", s)
    else
      h.fail("expected string body after set_body")
    end

class \nodoc\ iso _TestResponseContextStreamingNoOps is UnitTest
  fun name(): String => "response interceptor/streaming no-ops"

  fun apply(h: TestHelper) =>
    let buf = _BufferedResponse._streaming_complete(stallion.StatusOK, false)
    let ctx = ResponseContext._create(buf, _ResponseInterceptorTestRequest())
    h.assert_true(ctx.is_streaming())
    // All writes should be no-ops
    ctx.set_status(stallion.StatusNotFound)
    h.assert_true(ctx.status() is stallion.StatusOK,
      "set_status should be no-op for streaming")
    ctx.set_header("x-test", "value")
    h.assert_eq[USize](0, buf.headers.size(),
      "set_header should be no-op for streaming")
    ctx.add_header("x-test", "value")
    h.assert_eq[USize](0, buf.headers.size(),
      "add_header should be no-op for streaming")
    ctx.set_body("new body")
    h.assert_true(ctx.body() is None,
      "set_body should be no-op for streaming")

// --- _RunResponseInterceptors unit tests ---

class \nodoc\ iso _TestRunResponseInterceptorsNone is UnitTest
  fun name(): String => "response interceptor/run interceptors none"

  fun apply(h: TestHelper) =>
    let buf = _BufferedResponse._standard(stallion.StatusOK, "body", false)
    let ctx = ResponseContext._create(buf, _ResponseInterceptorTestRequest())
    _RunResponseInterceptors(ctx, None)
    // No error, headers unchanged
    h.assert_eq[USize](0, buf.headers.size())

class \nodoc\ iso _TestRunResponseInterceptorsSingle is UnitTest
  fun name(): String => "response interceptor/run interceptors single"

  fun apply(h: TestHelper) =>
    let buf = _BufferedResponse._standard(stallion.StatusOK, "body", false)
    let ctx = ResponseContext._create(buf, _ResponseInterceptorTestRequest())
    let interceptors: Array[ResponseInterceptor val] val =
      recover val
        [as ResponseInterceptor val:
          _AddHeaderResponseInterceptor("x-custom", "test-value")]
      end
    _RunResponseInterceptors(ctx, interceptors)
    var found = false
    for (n, v) in buf.headers.values() do
      if (n == "x-custom") and (v == "test-value") then found = true end
    end
    h.assert_true(found, "interceptor should have added header")

class \nodoc\ iso _TestRunResponseInterceptorsMultiple is UnitTest
  fun name(): String => "response interceptor/run interceptors multiple in order"

  fun apply(h: TestHelper) =>
    let buf = _BufferedResponse._standard(stallion.StatusOK, "body", false)
    let ctx = ResponseContext._create(buf, _ResponseInterceptorTestRequest())
    let interceptors: Array[ResponseInterceptor val] val =
      recover val
        [as ResponseInterceptor val:
          _AddHeaderResponseInterceptor("x-custom", "first")
          _AddHeaderResponseInterceptor("x-custom", "second")]
      end
    _RunResponseInterceptors(ctx, interceptors)
    // Last set_header wins (replaces)
    var count: USize = 0
    var last_value: String = ""
    for (n, v) in buf.headers.values() do
      if n == "x-custom" then
        count = count + 1
        last_value = v
      end
    end
    h.assert_eq[USize](1, count, "set_header should replace")
    h.assert_eq[String]("second", last_value, "last interceptor wins")

// --- _ConcatResponseInterceptors unit tests ---

class \nodoc\ iso _TestConcatResponseInterceptorsNone is UnitTest
  fun name(): String => "response interceptor/concat none"

  fun apply(h: TestHelper) =>
    h.assert_true(_ConcatResponseInterceptors(None, None) is None)

class \nodoc\ iso _TestConcatResponseInterceptorsBoth is UnitTest
  fun name(): String => "response interceptor/concat both"

  fun apply(h: TestHelper) =>
    let outer: Array[ResponseInterceptor val] val =
      recover val [as ResponseInterceptor val: _NoOpResponseInterceptor] end
    let inner: Array[ResponseInterceptor val] val =
      recover val [as ResponseInterceptor val: _NoOpResponseInterceptor] end
    match _ConcatResponseInterceptors(outer, inner)
    | let combined: Array[ResponseInterceptor val] val =>
      h.assert_eq[USize](2, combined.size())
    else
      h.fail("expected combined array")
    end

class \nodoc\ iso _TestConcatResponseInterceptorsOuterOnly is UnitTest
  fun name(): String => "response interceptor/concat outer only"

  fun apply(h: TestHelper) =>
    let outer: Array[ResponseInterceptor val] val =
      recover val [as ResponseInterceptor val: _NoOpResponseInterceptor] end
    match _ConcatResponseInterceptors(outer, None)
    | let result: Array[ResponseInterceptor val] val =>
      h.assert_eq[USize](1, result.size())
    else
      h.fail("expected array")
    end

class \nodoc\ iso _TestConcatResponseInterceptorsInnerOnly is UnitTest
  fun name(): String => "response interceptor/concat inner only"

  fun apply(h: TestHelper) =>
    let inner: Array[ResponseInterceptor val] val =
      recover val [as ResponseInterceptor val: _NoOpResponseInterceptor] end
    match _ConcatResponseInterceptors(None, inner)
    | let result: Array[ResponseInterceptor val] val =>
      h.assert_eq[USize](1, result.size())
    else
      h.fail("expected array")
    end

// --- Integration test infrastructure ---

actor \nodoc\ _TestResponseInterceptorListener is lori.TCPListenerActor
  """Listener for response interceptor integration tests."""
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig
  let _router: _Router val
  let _timers: Timers tag
  let _h: TestHelper
  let _run_client:
    {(TestHelper, String, _TestResponseInterceptorListener)} val

  new create(auth: lori.TCPListenAuth, config: stallion.ServerConfig,
    router: _Router val, h: TestHelper,
    run_client:
      {(TestHelper, String, _TestResponseInterceptorListener)} val)
  =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = config
    _router = router
    _timers = Timers
    _h = h
    _run_client = run_client
    _tcp_listener = lori.TCPListener(auth, config.host, config.port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    _Connection(_server_auth, fd, _config, _router, _timers, 0)

  fun ref _on_listening() =>
    try
      (_, let port) = _tcp_listener.local_address().name()?
      _run_client(_h, port, this)
    else
      _h.fail("could not get listener port")
      _h.complete(false)
    end

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")
    _h.complete(false)

  be dispose() =>
    _tcp_listener.close()
    _timers.dispose()

actor \nodoc\ _TestResponseInterceptorClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """TCP client that checks for an expected string in the response."""
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String
  let _expected: String
  let _listener: _TestResponseInterceptorListener
  var _response: String iso = recover iso String end

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String, expected: String,
    listener: _TestResponseInterceptorListener)
  =>
    _h = h
    _request = request
    _expected = expected
    _listener = listener
    _tcp_connection = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let response_str: String val = _response.clone()
    if response_str.contains(_expected) then
      _tcp_connection.close()
      _listener.dispose()
      _h.complete(true)
    end

  fun ref _on_closed() => None

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("connection failed")
    _listener.dispose()
    _h.complete(false)

primitive \nodoc\ _ResponseInterceptorIntegrationHelpers
  fun run_test(h: TestHelper, router: _Router val,
    request: String, expected: String)
  =>
    h.long_test(5_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    _TestResponseInterceptorListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestResponseInterceptorListener) =>
        _TestResponseInterceptorClient(connect_auth, host, port, h',
          request, expected, listener)
      })

// --- Integration tests ---

class \nodoc\ iso _TestResponseInterceptorSetHeaderIntegration is UnitTest
  """Response interceptor adds a header on a normal response."""
  fun name(): String => "integration/response interceptor set header"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let interceptors: Array[ResponseInterceptor val] val =
      recover val
        [as ResponseInterceptor val:
          _AddHeaderResponseInterceptor("x-custom", "test-value")]
      end
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/", _HelloFactory, interceptors)
    let router = builder.build()
    _ResponseInterceptorIntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "x-custom: test-value")

class \nodoc\ iso _TestResponseInterceptorOn404 is UnitTest
  """App-level response interceptor adds a header on a 404 response."""
  fun name(): String => "integration/response interceptor on 404"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let interceptors: Array[ResponseInterceptor val] val =
      recover val
        [as ResponseInterceptor val:
          _AddHeaderResponseInterceptor("x-custom", "on-404")]
      end
    let builder = _RouterBuilder
    // Register app-level interceptors on root node
    builder.add_interceptors("", None, interceptors)
    builder.add(stallion.GET, "/exists", _HelloFactory)
    let router = builder.build()
    _ResponseInterceptorIntegrationHelpers.run_test(h, router,
      "GET /nonexistent HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "x-custom: on-404")

class \nodoc\ iso _TestResponseInterceptorOnRejectIntercept is UnitTest
  """Response interceptor adds a header on a request interceptor short-circuit."""
  fun name(): String => "integration/response interceptor on reject"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let response_interceptors: Array[ResponseInterceptor val] val =
      recover val
        [as ResponseInterceptor val:
          _AddHeaderResponseInterceptor("x-custom", "on-reject")]
      end
    let request_interceptors: Array[RequestInterceptor val] val =
      recover val [as RequestInterceptor val: _RejectInterceptor] end
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/", _HelloFactory, response_interceptors,
      request_interceptors)
    let router = builder.build()
    _ResponseInterceptorIntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "x-custom: on-reject")

class \nodoc\ iso _TestResponseInterceptorSetBodyIntegration is UnitTest
  """Response interceptor replaces body, Content-Length auto-updated."""
  fun name(): String => "integration/response interceptor set body"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let interceptors: Array[ResponseInterceptor val] val =
      recover val
        [as ResponseInterceptor val:
          _SetBodyResponseInterceptor("replaced-body")]
      end
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/", _HelloFactory, interceptors)
    let router = builder.build()
    _ResponseInterceptorIntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "replaced-body")

class \nodoc\ iso _TestResponseInterceptorStreamingIntegration is UnitTest
  """Response interceptor header write is no-op for streaming responses."""
  fun name(): String => "integration/response interceptor streaming no-op"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let interceptors: Array[ResponseInterceptor val] val =
      recover val
        [as ResponseInterceptor val:
          _AddHeaderResponseInterceptor("x-after-stream", "should-not-appear")]
      end
    let builder = _RouterBuilder
    builder.add(stallion.GET, "/", _StreamingFactory, interceptors)
    let router = builder.build()
    h.long_test(5_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    _TestResponseInterceptorListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestResponseInterceptorListener) =>
        _TestStreamingNoOpClient(connect_auth, host, port, h',
          "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
          "chunk-1;", "x-after-stream", listener)
      })

class \nodoc\ iso _TestResponseInterceptorGroupOn404 is UnitTest
  """Group response interceptor runs on 404 under the group's prefix."""
  fun name(): String => "integration/response interceptor group on 404"
  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let interceptors: Array[ResponseInterceptor val] val =
      recover val
        [as ResponseInterceptor val:
          _AddHeaderResponseInterceptor("x-group", "api-404")]
      end
    let builder = _RouterBuilder
    builder.add_interceptors("/api", None, interceptors)
    builder.add(stallion.GET, "/api/users", _HelloFactory)
    let router = builder.build()
    _ResponseInterceptorIntegrationHelpers.run_test(h, router,
      "GET /api/nonexistent HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "x-group: api-404")

actor \nodoc\ _TestStreamingNoOpClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """
  TCP client for streaming no-op test: expects chunk data present AND
  a forbidden header absent.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String
  let _expect: String
  let _forbid: String
  let _listener: _TestResponseInterceptorListener
  var _response: String iso = recover iso String end

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String, expect: String,
    forbid: String, listener: _TestResponseInterceptorListener)
  =>
    _h = h
    _request = request
    _expect = expect
    _forbid = forbid
    _listener = listener
    _tcp_connection = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let response_str: String val = _response.clone()
    if response_str.contains(_expect) then
      _h.assert_false(response_str.contains(_forbid),
        "streaming response must not contain header: " + _forbid)
      _tcp_connection.close()
      _listener.dispose()
      _h.complete(true)
    end

  fun ref _on_closed() => None

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("connection failed")
    _listener.dispose()
    _h.complete(false)
