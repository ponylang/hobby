use "pony_test"
use "collections"
use "time"
use stallion = "stallion"
use lori = "lori"
use "net"

primitive \nodoc\ _TestIntegrationList
  fun tests(test: PonyTest) =>
    test(_TestBasicGet)
    test(_TestUnknownPath404)
    test(_TestNamedParams)
    test(_TestPostWithBody)
    test(_TestMiddlewareData)
    test(_TestMiddlewareShortCircuit)
    test(_TestMultipleRoutes)
    test(_TestGroupedRoute)
    test(_TestGroupMiddlewareIntegration)
    test(_TestAppMiddlewareIntegration)
    test(_TestNestedGroupIntegration)
    test(_TestStreamingResponse)
    test(_TestPipelinedStreaming)
    test(_TestHeadFallbackToGet)
    test(_TestHeadExplicitRoute)
    test(_TestHead404)
    test(_TestHeadWithMiddleware)
    test(_TestHeadStreamingHandler)
    test(_TestHeadPostOnlyRoute)
    test(_TestHeadStreamingPipelinedGet)
    test(_TestAsyncHandler)
    test(_TestBeforeMiddlewareError500)
    test(_TestStreamingChunkedNotSupported)
    test(_TestHandlerTimeout504)
    test(_TestAfterMiddlewareSetHeader)
    test(_TestStreamingTimeout)
    test(_TestOnClosedDispose)
    test(_TestPipelinedHandlerInProgress)
    test(_TestRespondAfterDispose)
    test(_TestPipelinedMultipleRequests)
    test(_TestNormalCompletionWithTimeout)
    test(_TestOnClosedStreamingDispose)
    test(_TestBeforeMiddlewareRespondWithHeaders)
    test(_TestAfterMiddlewareAddHeader)
    test(_TestStreamingAfterMiddleware)

// --- Test helpers ---

primitive \nodoc\ _TestHost
  fun apply(): String =>
    ifdef linux then "127.0.0.2" else "localhost" end

actor \nodoc\ _TestClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """Simple TCP client that sends raw HTTP and collects the response."""
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String
  let _expected: String
  let _listener: _TestIntegrationListener
  var _response: String iso = recover iso String end

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String, expected: String,
    listener: _TestIntegrationListener)
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

actor \nodoc\ _TestIntegrationListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig
  let _router: _Router val
  let _timers: Timers tag
  let _h: TestHelper
  let _run_client:
    {(TestHelper, String, _TestIntegrationListener)} val

  new create(auth: lori.TCPListenAuth, config: stallion.ServerConfig,
    router: _Router val, h: TestHelper,
    run_client:
      {(TestHelper, String, _TestIntegrationListener)} val)
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

// --- Test factories ---

primitive \nodoc\ _HelloFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    RequestHandler(consume ctx)
      .respond(stallion.StatusOK, "Hello from Hobby!")

primitive \nodoc\ _GreetFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    let handler = RequestHandler(consume ctx)
    try
      let name = handler.param("name")?
      handler.respond(stallion.StatusOK, "Hello, " + name + "!")
    else
      handler.respond(stallion.StatusBadRequest, "Bad Request")
    end

primitive \nodoc\ _EchoBodyFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    let handler = RequestHandler(consume ctx)
    handler.respond(stallion.StatusOK, handler.body())

primitive \nodoc\ _DataReadFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    let handler = RequestHandler(consume ctx)
    try
      let value = handler.get[String]("test_key")?
      handler.respond(stallion.StatusOK, value)
    else
      handler.respond(stallion.StatusInternalServerError, "wrong type")
    end

// --- Test middleware ---

class \nodoc\ val _SetDataMiddleware is Middleware
  let _key: String
  let _value: String
  new val create(key: String, value: String) =>
    _key = key
    _value = value
  fun before(ctx: BeforeContext ref) =>
    ctx.set(_key, _value)

class \nodoc\ val _ShortCircuitMiddleware is Middleware
  fun before(ctx: BeforeContext ref) =>
    ctx.respond(stallion.StatusUnauthorized, "Unauthorized")

class \nodoc\ val _RespondWithHeadersMiddleware is Middleware
  """Before-middleware that short-circuits with explicit headers."""
  fun before(ctx: BeforeContext ref) =>
    let headers: stallion.Headers val = recover val
      stallion.Headers
        .> set("X-Middleware", "custom-value")
        .> set("Content-Length", "9")
    end
    ctx.respond_with_headers(stallion.StatusForbidden, headers, "Forbidden")

class \nodoc\ val _AddMultiHeaderMiddleware is Middleware
  """After-middleware that adds multiple Set-Cookie headers."""
  fun before(ctx: BeforeContext ref) => None
  fun after(ctx: AfterContext ref) =>
    ctx.add_header("Set-Cookie", "a=1")
    ctx.add_header("Set-Cookie", "b=2")

class \nodoc\ val _StreamingAfterHeaderMiddleware is Middleware
  """After-middleware that tries to set a header — no-op for streaming."""
  fun before(ctx: BeforeContext ref) => None
  fun after(ctx: AfterContext ref) =>
    ctx.set_header("x-after-stream", "should-not-appear")

// --- Helpers ---

primitive \nodoc\ _IntegrationHelpers
  fun build_router(
    routes: Array[(stallion.Method, String, HandlerFactory,
      (Array[Middleware val] val | None))] val): _Router val
  =>
    let builder = _RouterBuilder
    for (method, path, factory, middleware) in routes.values() do
      builder.add(method, path, factory, middleware)
    end
    builder.build()

  fun run_test(h: TestHelper, router: _Router val,
    request: String, expected: String)
  =>
    h.long_test(5_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    _TestIntegrationListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestIntegrationListener) =>
        _TestClient(connect_auth, host, port, h', request, expected,
          listener)
      })

// --- Integration tests ---

class \nodoc\ iso _TestBasicGet is UnitTest
  """Basic GET returns 200 + body."""
  fun name(): String => "integration/basic GET"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello from Hobby!")

class \nodoc\ iso _TestUnknownPath404 is UnitTest
  """Unknown path returns 404."""
  fun name(): String => "integration/unknown path 404"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /nonexistent HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Not Found")

class \nodoc\ iso _TestNamedParams is UnitTest
  """Named params delivered to handler."""
  fun name(): String => "integration/named params"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/greet/:name", _GreetFactory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /greet/World HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello, World!")

class \nodoc\ iso _TestPostWithBody is UnitTest
  """POST with body: handler receives body bytes."""
  fun name(): String => "integration/POST with body"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.POST, "/echo", _EchoBodyFactory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "POST /echo HTTP/1.1\r\nHost: localhost\r\n" +
        "Content-Length: 11\r\n\r\nHello Body!",
      "Hello Body!")

class \nodoc\ iso _TestMiddlewareData is UnitTest
  """Middleware sets context data, handler reads it."""
  fun name(): String => "integration/middleware data"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _SetDataMiddleware("test_key", "middleware_value")]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/data", _DataReadFactory, mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /data HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "middleware_value")

class \nodoc\ iso _TestMiddlewareShortCircuit is UnitTest
  """Middleware short-circuits with 401, handler NOT invoked."""
  fun name(): String => "integration/middleware short-circuit"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _ShortCircuitMiddleware]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/private", _HelloFactory, mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /private HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Unauthorized")

class \nodoc\ iso _TestMultipleRoutes is UnitTest
  """Multiple routes dispatch correctly."""
  fun name(): String => "integration/multiple routes"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [ (stallion.GET, "/", _HelloFactory, None)
        (stallion.GET, "/greet/:name", _GreetFactory, None) ]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /greet/Pony HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello, Pony!")

class \nodoc\ iso _TestGroupedRoute is UnitTest
  """Route at a group-prefixed path resolves correctly."""
  fun name(): String => "integration/grouped route"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let joined = _JoinPath("/api", "/users")
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, joined, _HelloFactory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /api/users HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello from Hobby!")

class \nodoc\ iso _TestGroupMiddlewareIntegration is UnitTest
  """Group middleware short-circuits with 401."""
  fun name(): String => "integration/group middleware"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let group_mw: Array[Middleware val] val = recover val
      [as Middleware val: _ShortCircuitMiddleware]
    end
    let joined = _JoinPath("/api", "/secret")
    let combined_mw = _ConcatMiddleware(group_mw, None)
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, joined, _HelloFactory, combined_mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /api/secret HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Unauthorized")

class \nodoc\ iso _TestAppMiddlewareIntegration is UnitTest
  """App-level middleware sets data that the handler reads."""
  fun name(): String => "integration/app middleware"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let app_mw: Array[Middleware val] val = recover val
      [as Middleware val:
        _SetDataMiddleware("test_key", "from_app_middleware")]
    end
    let combined_mw = _ConcatMiddleware(app_mw, None)
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/data", _DataReadFactory, combined_mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /data HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "from_app_middleware")

class \nodoc\ iso _TestNestedGroupIntegration is UnitTest
  """Nested group path resolves correctly through the HTTP stack."""
  fun name(): String => "integration/nested group"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let inner_path = _JoinPath("/admin", "/dashboard")
    let outer_path = _JoinPath("/api", inner_path)
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, outer_path, _HelloFactory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /api/admin/dashboard HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello from Hobby!")

// --- Async handler test ---

actor \nodoc\ _AsyncTestService
  """Simulates an async service via self-directed message."""
  be query(requester: _AsyncTestHandler tag) =>
    requester._result("async-response-data")

actor \nodoc\ _AsyncTestHandler is HandlerReceiver
  """Handler that responds after an async callback."""
  embed _handler: RequestHandler

  new create(ctx: HandlerContext iso, service: _AsyncTestService tag) =>
    _handler = RequestHandler(consume ctx)
    service.query(this)

  be _result(data: String) =>
    _handler.respond(stallion.StatusOK, data)

  be dispose() => None
  be throttled() => None
  be unthrottled() => None

class \nodoc\ iso _TestAsyncHandler is UnitTest
  """Async handler responds after receiving a callback from a service."""
  fun name(): String => "integration/async handler"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let service = _AsyncTestService
    let factory: HandlerFactory = {(ctx)(service) =>
      _AsyncTestHandler(consume ctx, service)
    } val
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", factory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "async-response-data")

// --- Before-middleware error test ---

class \nodoc\ val _ErrorMiddleware is Middleware
  """Middleware whose before phase errors without responding."""
  fun before(ctx: BeforeContext ref) ? =>
    error

class \nodoc\ iso _TestBeforeMiddlewareError500 is UnitTest
  """Before-middleware error without responding produces 500."""
  fun name(): String => "integration/before middleware error 500"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _ErrorMiddleware]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Internal Server Error")

// --- Streaming chunked not supported test ---

actor \nodoc\ _StreamingFallbackHandler is HandlerReceiver
  """Starts streaming with fallback for ChunkedNotSupported."""
  embed _handler: RequestHandler

  new create(ctx: HandlerContext iso) =>
    _handler = RequestHandler(consume ctx)
    match _handler.start_streaming(stallion.StatusOK)
    | StreamingStarted => _send()
    | stallion.ChunkedNotSupported =>
      _handler.respond(stallion.StatusOK, "chunked-fallback")
    | BodyNotNeeded => None
    end

  be _send() =>
    _handler.send_chunk("streamed")
    _handler.finish()

  be dispose() => None
  be throttled() => None
  be unthrottled() => None

class \nodoc\ iso _TestStreamingChunkedNotSupported is UnitTest
  """HTTP/1.0 request to streaming handler triggers ChunkedNotSupported fallback."""
  fun name(): String => "integration/streaming chunked not supported"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let factory: HandlerFactory = {(ctx) =>
      _StreamingFallbackHandler(consume ctx)
    } val
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", factory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n",
      "chunked-fallback")

// --- Streaming test handler actor ---

actor \nodoc\ _StreamingTestHandler is HandlerReceiver
  """Starts streaming and sends numbered chunks."""
  embed _handler: RequestHandler

  new create(ctx: HandlerContext iso) =>
    _handler = RequestHandler(consume ctx)
    match _handler.start_streaming(stallion.StatusOK)
    | StreamingStarted => _send()
    end

  be _send() =>
    _handler.send_chunk("chunk-1;")
    _handler.send_chunk("chunk-2;")
    _handler.send_chunk("chunk-3;")
    _handler.finish()

  be dispose() => None
  be throttled() => None
  be unthrottled() => None

primitive \nodoc\ _StreamingFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    _StreamingTestHandler(consume ctx)

// --- Pipelined streaming test handler actor ---

actor \nodoc\ _PipelinedStreamTestHandler is HandlerReceiver
  """Sends a single marker chunk and finishes."""
  embed _handler: RequestHandler

  new create(ctx: HandlerContext iso) =>
    _handler = RequestHandler(consume ctx)
    match _handler.start_streaming(stallion.StatusOK)
    | StreamingStarted => _send()
    end

  be _send() =>
    _handler.send_chunk("pipelined-ok")
    _handler.finish()

  be dispose() => None
  be throttled() => None
  be unthrottled() => None

primitive \nodoc\ _PipelinedStreamFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    _PipelinedStreamTestHandler(consume ctx)

// --- Streaming integration tests ---

class \nodoc\ iso _TestStreamingResponse is UnitTest
  """Streaming handler delivers chunks to the client."""
  fun name(): String => "integration/streaming response"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _StreamingFactory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "chunk-1;")

class \nodoc\ iso _TestPipelinedStreaming is UnitTest
  """
  Pipelined streaming request is buffered and processed after first stream
  finishes.
  """
  fun name(): String => "integration/pipelined streaming"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [ (stallion.GET, "/stream1", _StreamingFactory, None)
        (stallion.GET, "/stream2", _PipelinedStreamFactory, None) ]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /stream1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /stream2 HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "pipelined-ok")

// --- HEAD test helpers ---

actor \nodoc\ _TestHeadClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """
  TCP client for HEAD tests: checks that an expected header is present AND
  a forbidden body string is absent.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String
  let _expect_header: String
  let _forbid_body: String
  let _listener: _TestIntegrationListener
  var _response: String iso = recover iso String end

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String, expect_header: String,
    forbid_body: String, listener: _TestIntegrationListener)
  =>
    _h = h
    _request = request
    _expect_header = expect_header
    _forbid_body = forbid_body
    _listener = listener
    _tcp_connection = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let response_str: String val = _response.clone()
    if response_str.contains(_expect_header) then
      _h.assert_false(response_str.contains(_forbid_body),
        "HEAD response must not contain body: " + _forbid_body)
      _tcp_connection.close()
      _listener.dispose()
      _h.complete(true)
    end

  fun ref _on_closed() => None

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("connection failed")
    _listener.dispose()
    _h.complete(false)

// --- HEAD test factory ---

primitive \nodoc\ _HeadOnlyFactory
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    RequestHandler(consume ctx)
      .respond(stallion.StatusOK, "HEAD only response")

// --- HEAD helpers ---

primitive \nodoc\ _HeadIntegrationHelpers
  fun run_head_test(h: TestHelper, router: _Router val,
    request: String, expect_header: String, forbid_body: String)
  =>
    h.long_test(5_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    _TestIntegrationListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestIntegrationListener) =>
        _TestHeadClient(connect_auth, host, port, h', request,
          expect_header, forbid_body, listener)
      })

// --- HEAD integration tests ---

class \nodoc\ iso _TestHeadFallbackToGet is UnitTest
  """HEAD with no explicit HEAD route falls back to GET handler."""
  fun name(): String => "integration/HEAD fallback to GET"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, None)]
    end)
    _HeadIntegrationHelpers.run_head_test(h, router,
      "HEAD / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Content-Length: 17", "Hello from Hobby!")

class \nodoc\ iso _TestHeadExplicitRoute is UnitTest
  """Explicit HEAD route takes precedence over GET fallback."""
  fun name(): String => "integration/HEAD explicit route"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [ (stallion.HEAD, "/", _HeadOnlyFactory, None)
        (stallion.GET, "/", _HelloFactory, None) ]
    end)
    _HeadIntegrationHelpers.run_head_test(h, router,
      "HEAD / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Content-Length: 18", "HEAD only response")

class \nodoc\ iso _TestHead404 is UnitTest
  """HEAD to nonexistent path returns 404 headers without body."""
  fun name(): String => "integration/HEAD 404"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, None)]
    end)
    // Forbid "\r\n\r\nNot Found" (body after headers), not just "Not Found"
    // which also appears in the status line "404 Not Found".
    _HeadIntegrationHelpers.run_head_test(h, router,
      "HEAD /nonexistent HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Content-Length: 9", "\r\n\r\nNot Found")

class \nodoc\ iso _TestHeadWithMiddleware is UnitTest
  """HEAD with middleware: body suppressed, headers preserved."""
  fun name(): String => "integration/HEAD with middleware"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _SetDataMiddleware("test_key", "middleware_value")]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/data", _DataReadFactory, mw)]
    end)
    _HeadIntegrationHelpers.run_head_test(h, router,
      "HEAD /data HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Content-Length: 16", "middleware_value")

class \nodoc\ iso _TestHeadStreamingHandler is UnitTest
  """HEAD to streaming handler: returns 200 OK without chunks."""
  fun name(): String => "integration/HEAD streaming handler"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _StreamingFactory, None)]
    end)
    _HeadIntegrationHelpers.run_head_test(h, router,
      "HEAD / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "200 OK", "chunk-1;")

class \nodoc\ iso _TestHeadPostOnlyRoute is UnitTest
  """HEAD to POST-only route returns 404 (HEAD only falls back to GET)."""
  fun name(): String => "integration/HEAD on POST-only route"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.POST, "/echo", _EchoBodyFactory, None)]
    end)
    // Forbid "\r\n\r\nNot Found" (body after headers), not just "Not Found"
    // which also appears in the status line "404 Not Found".
    _HeadIntegrationHelpers.run_head_test(h, router,
      "HEAD /echo HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Content-Length: 9", "\r\n\r\nNot Found")

class \nodoc\ iso _TestHeadStreamingPipelinedGet is UnitTest
  """
  HEAD to streaming handler followed by pipelined GET: HEAD completes without
  setting streaming mode, so the GET is NOT buffered and processes immediately.
  """
  fun name(): String => "integration/HEAD streaming + pipelined GET"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _StreamingFactory, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "HEAD / HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "chunk-1;")

// --- Handler timeout test ---

primitive \nodoc\ _NeverRespondFactory
  """Factory that creates a handler actor that never responds."""
  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    _NeverRespondHandler(consume ctx)

actor \nodoc\ _NeverRespondHandler is HandlerReceiver
  embed _handler: RequestHandler

  new create(ctx: HandlerContext iso) =>
    _handler = RequestHandler(consume ctx)
    // Intentionally never responds — timeout should fire

  be dispose() => None
  be throttled() => None
  be unthrottled() => None

actor \nodoc\ _TestTimeoutListener is lori.TCPListenerActor
  """Listener that creates connections with a short handler timeout."""
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig
  let _router: _Router val
  let _timers: Timers tag
  let _h: TestHelper
  let _run_client:
    {(TestHelper, String, _TestTimeoutListener)} val

  new create(auth: lori.TCPListenAuth, config: stallion.ServerConfig,
    router: _Router val, h: TestHelper,
    run_client:
      {(TestHelper, String, _TestTimeoutListener)} val)
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
    // 500ms timeout in nanoseconds
    _Connection(_server_auth, fd, _config, _router, _timers, 500_000_000)

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

actor \nodoc\ _TestTimeoutClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """TCP client for timeout tests that expects 504."""
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String
  let _listener: _TestTimeoutListener
  var _response: String iso = recover iso String end

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String, listener: _TestTimeoutListener)
  =>
    _h = h
    _request = request
    _listener = listener
    _tcp_connection = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let response_str: String val = _response.clone()
    if response_str.contains("504") or
      response_str.contains("Gateway Timeout")
    then
      _tcp_connection.close()
      _listener.dispose()
      _h.complete(true)
    end

  fun ref _on_closed() => None

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("connection failed")
    _listener.dispose()
    _h.complete(false)

class \nodoc\ iso _TestHandlerTimeout504 is UnitTest
  """Handler that never responds gets 504 after timeout."""
  fun name(): String => "integration/handler timeout 504"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _NeverRespondFactory, None)]
    end)
    _TestTimeoutListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestTimeoutListener) =>
        _TestTimeoutClient(connect_auth, host, port, h',
          "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
          listener)
      })

// --- After-middleware header modification test ---

class \nodoc\ val _AddHeaderMiddleware is Middleware
  """After-middleware that adds a custom header to the response."""
  fun before(ctx: BeforeContext ref) => None
  fun after(ctx: AfterContext ref) =>
    ctx.set_header("X-Custom", "test-value")

class \nodoc\ iso _TestAfterMiddlewareSetHeader is UnitTest
  """After-middleware can add headers to the response."""
  fun name(): String => "integration/after middleware set header"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _AddHeaderMiddleware]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "x-custom: test-value")

// --- Streaming timeout test ---

actor \nodoc\ _StreamTimeoutHandler is HandlerReceiver
  """Starts streaming, sends one chunk, never finishes."""
  embed _handler: RequestHandler

  new create(ctx: HandlerContext iso) =>
    _handler = RequestHandler(consume ctx)
    match _handler.start_streaming(stallion.StatusOK)
    | StreamingStarted =>
      _handler.send_chunk("stream-timeout-chunk")
      // Intentionally never calls finish() — timeout should close connection
    end

  be dispose() => None
  be throttled() => None
  be unthrottled() => None

actor \nodoc\ _TestStreamTimeoutClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """Accumulates response; expects chunk received then connection closed."""
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String
  let _listener: _TestTimeoutListener
  var _response: String iso = recover iso String end
  var _got_chunk: Bool = false

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String, listener: _TestTimeoutListener)
  =>
    _h = h
    _request = request
    _listener = listener
    _tcp_connection = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let response_str: String val = _response.clone()
    if response_str.contains("stream-timeout-chunk") then
      _got_chunk = true
    end

  fun ref _on_closed() =>
    if _got_chunk then
      _listener.dispose()
      _h.complete(true)
    else
      _h.fail("connection closed without receiving chunk")
      _listener.dispose()
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("connection failed")
    _listener.dispose()
    _h.complete(false)

class \nodoc\ iso _TestStreamingTimeout is UnitTest
  """Streaming handler that never finishes gets connection closed after timeout."""
  fun name(): String => "integration/streaming timeout"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    let factory: HandlerFactory = {(ctx) =>
      _StreamTimeoutHandler(consume ctx)
    } val
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", factory, None)]
    end)
    _TestTimeoutListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestTimeoutListener) =>
        _TestStreamTimeoutClient(connect_auth, host, port, h',
          "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
          listener)
      })

// --- on_closed dispose test ---

actor \nodoc\ _DisposeCoordinator
  """Receives handler disposal notification and completes the test."""
  var _h: (TestHelper | None) = None
  var _listener: (_TestIntegrationListener | None) = None

  be setup(h: TestHelper, listener: _TestIntegrationListener) =>
    _h = h
    _listener = listener

  be handler_disposed() =>
    match (_h, _listener)
    | (let h: TestHelper, let listener: _TestIntegrationListener) =>
      listener.dispose()
      h.complete(true)
    end

actor \nodoc\ _WaitForDisposeHandler is HandlerReceiver
  """Handler that never responds. Reports disposal to coordinator."""
  embed _handler: RequestHandler
  let _coordinator: _DisposeCoordinator tag

  new create(ctx: HandlerContext iso,
    coordinator: _DisposeCoordinator tag)
  =>
    _handler = RequestHandler(consume ctx)
    _coordinator = coordinator
    // Intentionally never responds — waits for dispose

  be dispose() =>
    _coordinator.handler_disposed()

  be throttled() => None
  be unthrottled() => None

actor \nodoc\ _DisconnectAfterSendClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """Sends a request then closes the connection after a short delay."""
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String)
  =>
    _h = h
    _request = request
    _tcp_connection = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)
    _disconnect_soon()

  be _disconnect_soon() =>
    // Second behavior hop gives the server time to process
    _disconnect_now()

  be _disconnect_now() =>
    _tcp_connection.close()

  fun ref _on_received(data: Array[U8] iso) => None
  fun ref _on_closed() => None

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("connection failed")
    _h.complete(false)

class \nodoc\ iso _TestOnClosedDispose is UnitTest
  """Client disconnect during active handler fires dispose()."""
  fun name(): String => "integration/on_closed dispose"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    let coordinator = _DisposeCoordinator
    let factory: HandlerFactory = {(ctx)(coordinator) =>
      _WaitForDisposeHandler(consume ctx, coordinator)
    } val
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", factory, None)]
    end)
    _TestIntegrationListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestIntegrationListener)(coordinator) =>
        coordinator.setup(h', listener)
        _DisconnectAfterSendClient(connect_auth, host, port, h',
          "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
      })

// --- Pipelined handler-in-progress test ---

actor \nodoc\ _DelayedResponseHandler is HandlerReceiver
  """Handler that responds via a self-directed behavior hop."""
  embed _handler: RequestHandler

  new create(ctx: HandlerContext iso) =>
    _handler = RequestHandler(consume ctx)
    _respond_now()

  be _respond_now() =>
    _handler.respond(stallion.StatusOK, "delayed-first")

  be dispose() => None
  be throttled() => None
  be unthrottled() => None

class \nodoc\ iso _TestPipelinedHandlerInProgress is UnitTest
  """Pipelined request during _HandlerInProgress is buffered and drained."""
  fun name(): String => "integration/pipelined handler in progress"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let factory: HandlerFactory = {(ctx) =>
      _DelayedResponseHandler(consume ctx)
    } val
    let router = _IntegrationHelpers.build_router(recover val
      [ (stallion.GET, "/slow", factory, None)
        (stallion.GET, "/fast", _HelloFactory, None) ]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /slow HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /fast HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello from Hobby!")

class \nodoc\ iso _TestPipelinedMultipleRequests is UnitTest
  """Three pipelined requests where the first two are async: all three drain."""
  fun name(): String => "integration/pipelined multiple requests"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let factory: HandlerFactory = {(ctx) =>
      _DelayedResponseHandler(consume ctx)
    } val
    let router = _IntegrationHelpers.build_router(recover val
      [ (stallion.GET, "/slow", factory, None)
        (stallion.GET, "/fast", _HelloFactory, None) ]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /slow HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /slow HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /fast HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello from Hobby!")

// --- Respond after dispose (late response) test ---

actor \nodoc\ _LateRespondHandler is HandlerReceiver
  """Handler that responds after its timeout has expired."""
  embed _handler: RequestHandler
  let _timers: Timers

  new create(ctx: HandlerContext iso) =>
    _handler = RequestHandler(consume ctx)
    _timers = Timers
    // Fire after 1 second — timeout is 500ms, so this fires after disposal
    let timer = Timer(
      _LateRespondNotify(this), 1_000_000_000, 0)
    _timers(consume timer)

  be _respond_now() =>
    _handler.respond(stallion.StatusOK, "late-response")
    _timers.dispose()

  be dispose() =>
    // Intentionally does NOT cancel timer — tests that late response is
    // dropped by token+state check in _Connection
    None

  be throttled() => None
  be unthrottled() => None

class \nodoc\ iso _LateRespondNotify is TimerNotify
  """Fires _respond_now on the handler after delay."""
  let _handler: _LateRespondHandler tag

  new iso create(handler: _LateRespondHandler tag) =>
    _handler = handler

  fun ref apply(timer: Timer, count: U64): Bool =>
    _handler._respond_now()
    false

class \nodoc\ iso _TestRespondAfterDispose is UnitTest
  """Late response after timeout is dropped; client sees 504."""
  fun name(): String => "integration/respond after dispose"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    let factory: HandlerFactory = {(ctx) =>
      _LateRespondHandler(consume ctx)
    } val
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", factory, None)]
    end)
    _TestTimeoutListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestTimeoutListener) =>
        _TestTimeoutClient(connect_auth, host, port, h',
          "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
          listener)
      })

// --- Normal completion with timeout test ---

actor \nodoc\ _TestTimeoutNormalClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """TCP client that expects a normal response, fails on 504."""
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String
  let _listener: _TestTimeoutListener
  var _response: String iso = recover iso String end

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String, listener: _TestTimeoutListener)
  =>
    _h = h
    _request = request
    _listener = listener
    _tcp_connection = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let response_str: String val = _response.clone()
    if response_str.contains("Hello from Hobby!") then
      _tcp_connection.close()
      _listener.dispose()
      _h.complete(true)
    elseif response_str.contains("Gateway Timeout") then
      _h.fail("unexpected 504 — handler completed before timeout")
      _tcp_connection.close()
      _listener.dispose()
      _h.complete(false)
    end

  fun ref _on_closed() => None

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("connection failed")
    _listener.dispose()
    _h.complete(false)

class \nodoc\ iso _TestNormalCompletionWithTimeout is UnitTest
  """Handler completes before timeout — no 504."""
  fun name(): String => "integration/normal completion with timeout"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, None)]
    end)
    _TestTimeoutListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestTimeoutListener) =>
        _TestTimeoutNormalClient(connect_auth, host, port, h',
          "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
          listener)
      })

// --- Streaming dispose test ---

actor \nodoc\ _StreamingDisposeHandler is HandlerReceiver
  """Starts streaming, sends a chunk, waits. Reports disposal."""
  embed _handler: RequestHandler
  let _coordinator: _DisposeCoordinator tag

  new create(ctx: HandlerContext iso,
    coordinator: _DisposeCoordinator tag)
  =>
    _handler = RequestHandler(consume ctx)
    _coordinator = coordinator
    match _handler.start_streaming(stallion.StatusOK)
    | StreamingStarted =>
      _handler.send_chunk("streaming-data")
      // Intentionally never calls finish() — waits for dispose
    end

  be dispose() =>
    _coordinator.handler_disposed()

  be throttled() => None
  be unthrottled() => None

class \nodoc\ iso _TestOnClosedStreamingDispose is UnitTest
  """Client disconnect during streaming fires dispose()."""
  fun name(): String => "integration/on_closed streaming dispose"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    let coordinator = _DisposeCoordinator
    let factory: HandlerFactory = {(ctx)(coordinator) =>
      _StreamingDisposeHandler(consume ctx, coordinator)
    } val
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", factory, None)]
    end)
    _TestIntegrationListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestIntegrationListener)(coordinator) =>
        coordinator.setup(h', listener)
        _DisconnectAfterSendClient(connect_auth, host, port, h',
          "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
      })

// --- BeforeContext.respond_with_headers() test ---

class \nodoc\ iso _TestBeforeMiddlewareRespondWithHeaders is UnitTest
  """Before-middleware respond_with_headers() sends explicit headers."""
  fun name(): String => "integration/before middleware respond with headers"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _RespondWithHeadersMiddleware]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "x-middleware: custom-value")

// --- AfterContext.add_header() test ---

class \nodoc\ iso _TestAfterMiddlewareAddHeader is UnitTest
  """After-middleware add_header() appends without removing existing entries."""
  fun name(): String => "integration/after middleware add header"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _AddMultiHeaderMiddleware]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloFactory, mw)]
    end)
    // Check for the first Set-Cookie header — if add_header() replaced
    // instead of appending, only the second (b=2) would survive.
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "set-cookie: a=1")

// --- Streaming after-middleware test ---

class \nodoc\ iso _TestStreamingAfterMiddleware is UnitTest
  """After-middleware header modification is silently ignored for streaming."""
  fun name(): String => "integration/streaming after middleware"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _StreamingAfterHeaderMiddleware]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _StreamingFactory, mw)]
    end)
    // Streaming data arrives; after-middleware header does not appear.
    _HeadIntegrationHelpers.run_head_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "chunk-1;", "x-after-stream")
