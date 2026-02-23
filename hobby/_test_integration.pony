use "pony_test"
use "collections"
use stallion = "stallion"
use lori = "lori"
use "net"

primitive _TestIntegrationList
  fun tests(test: PonyTest) =>
    test(_TestBasicGet)
    test(_TestUnknownPath404)
    test(_TestNamedParams)
    test(_TestPostWithBody)
    test(_TestMiddlewareData)
    test(_TestMiddlewareShortCircuit)
    test(_TestHandlerError500)
    test(_TestMultipleRoutes)
    test(_TestGroupedRoute)
    test(_TestGroupMiddlewareIntegration)
    test(_TestAppMiddlewareIntegration)
    test(_TestNestedGroupIntegration)
    test(_TestStreamingResponse)
    test(_TestStreamingErrorCleanup)
    test(_TestStreamingMiddlewareErrorCleanup)
    test(_TestPipelinedStreaming)
    test(_TestStreamingAlreadyResponded)
    test(_TestStreamingChunkedNotSupported)

// --- Test helpers ---

primitive _TestHost
  fun apply(): String =>
    ifdef linux then "127.0.0.2" else "localhost" end

actor _TestClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
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
      _h.assert_true(true)
      _tcp_connection.close()
      _listener.dispose()
      _h.complete(true)
    end

  fun ref _on_closed() => None

  fun ref _on_connection_failure() =>
    _h.fail("connection failed")
    _listener.dispose()
    _h.complete(false)

actor _TestIntegrationListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig
  let _router: _Router val
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
    _h = h
    _run_client = run_client
    _tcp_listener = lori.TCPListener(auth, config.host, config.port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    _Connection(_server_auth, fd, _config, _router)

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

// --- Test handlers ---

primitive _HelloHandler is Handler
  fun apply(ctx: Context ref) =>
    ctx.respond(stallion.StatusOK, "Hello from Hobby!")

class val _GreetHandler is Handler
  fun apply(ctx: Context ref) ? =>
    let name = ctx.param("name")?
    ctx.respond(stallion.StatusOK, "Hello, " + name + "!")

primitive _EchoBodyHandler is Handler
  fun apply(ctx: Context ref) =>
    ctx.respond(stallion.StatusOK, ctx.body())

primitive _DataReadHandler is Handler
  fun apply(ctx: Context ref) ? =>
    let value = ctx.get("test_key")?
    match value
    | let s: String => ctx.respond(stallion.StatusOK, s)
    else
      ctx.respond(stallion.StatusInternalServerError, "wrong type")
    end

primitive _ErrorHandler is Handler
  fun apply(ctx: Context ref) ? =>
    error

// --- Test middleware ---

class val _SetDataMiddleware is Middleware
  let _key: String
  let _value: String
  new val create(key: String, value: String) =>
    _key = key
    _value = value
  fun before(ctx: Context ref) =>
    ctx.set(_key, _value)

class val _ShortCircuitMiddleware is Middleware
  fun before(ctx: Context ref) =>
    ctx.respond(stallion.StatusUnauthorized, "Unauthorized")

// --- Helpers ---

primitive _IntegrationHelpers
  fun build_router(
    routes: Array[(stallion.Method, String, Handler,
      (Array[Middleware val] val | None))] val): _Router val
  =>
    let builder = _RouterBuilder
    for (method, path, handler, middleware) in routes.values() do
      builder.add(method, path, handler, middleware)
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
      [(stallion.GET, "/", _HelloHandler, None)]
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
      [(stallion.GET, "/", _HelloHandler, None)]
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
      [(stallion.GET, "/greet/:name", _GreetHandler, None)]
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
      [(stallion.POST, "/echo", _EchoBodyHandler, None)]
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
      [(stallion.GET, "/data", _DataReadHandler, mw)]
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
      [(stallion.GET, "/private", _HelloHandler, mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /private HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Unauthorized")

class \nodoc\ iso _TestHandlerError500 is UnitTest
  """Handler error produces 500."""
  fun name(): String => "integration/handler error 500"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/error", _ErrorHandler, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /error HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Internal Server Error")

class \nodoc\ iso _TestMultipleRoutes is UnitTest
  """Multiple routes dispatch correctly."""
  fun name(): String => "integration/multiple routes"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [ (stallion.GET, "/", _HelloHandler, None)
        (stallion.GET, "/greet/:name", _GreetHandler, None) ]
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
      [(stallion.GET, joined, _HelloHandler, None)]
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
      [(stallion.GET, joined, _HelloHandler, combined_mw)]
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
      [(stallion.GET, "/data", _DataReadHandler, combined_mw)]
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
      [(stallion.GET, outer_path, _HelloHandler, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /api/admin/dashboard HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "Hello from Hobby!")

// --- Streaming test handlers ---

primitive \nodoc\ _StreamingHandler is Handler
  """Starts streaming and passes sender to a producer."""
  fun apply(ctx: Context ref) ? =>
    match ctx.start_streaming(stallion.StatusOK)?
    | let sender: StreamSender tag =>
      _StreamingProducer(sender)
    end

actor \nodoc\ _StreamingProducer
  """Sends numbered chunks and finishes."""
  let _sender: StreamSender tag

  new create(sender: StreamSender tag) =>
    _sender = sender
    _send()

  be _send() =>
    _sender.send_chunk("chunk-1;")
    _sender.send_chunk("chunk-2;")
    _sender.send_chunk("chunk-3;")
    _sender.finish()

primitive \nodoc\ _StreamingErrorHandler is Handler
  """Starts streaming then errors — tests error cleanup."""
  fun apply(ctx: Context ref) ? =>
    ctx.start_streaming(stallion.StatusOK)?
    error

class \nodoc\ val _StreamingErrorMiddleware is Middleware
  """Starts streaming in before then errors — tests middleware error cleanup."""
  fun before(ctx: Context ref) ? =>
    ctx.start_streaming(stallion.StatusOK)?
    error

// --- Streaming integration tests ---

class \nodoc\ iso _TestStreamingResponse is UnitTest
  """Streaming handler delivers chunks to the client."""
  fun name(): String => "integration/streaming response"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _StreamingHandler, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "chunk-1;")

class \nodoc\ iso _TestStreamingErrorCleanup is UnitTest
  """Handler error after start_streaming sends terminal chunk."""
  fun name(): String => "integration/streaming error cleanup"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _StreamingErrorHandler, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "0\r\n")

class \nodoc\ iso _TestStreamingMiddlewareErrorCleanup is UnitTest
  """Middleware before error after start_streaming sends terminal chunk."""
  fun name(): String => "integration/streaming middleware error cleanup"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let mw: Array[Middleware val] val = recover val
      [as Middleware val: _StreamingErrorMiddleware]
    end
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _HelloHandler, mw)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "0\r\n")

// --- Pipelined streaming test handlers ---

primitive \nodoc\ _PipelinedStreamHandler is Handler
  """Starts streaming and passes sender to a producer that sends a marker."""
  fun apply(ctx: Context ref) ? =>
    match ctx.start_streaming(stallion.StatusOK)?
    | let sender: StreamSender tag =>
      _PipelinedStreamProducer(sender)
    end

actor \nodoc\ _PipelinedStreamProducer
  """Sends a single marker chunk and finishes."""
  let _sender: StreamSender tag

  new create(sender: StreamSender tag) =>
    _sender = sender
    _send()

  be _send() =>
    _sender.send_chunk("pipelined-ok")
    _sender.finish()

// --- Pipelined streaming integration test ---

class \nodoc\ iso _TestPipelinedStreaming is UnitTest
  """
  Pipelined streaming request is buffered and processed after first stream
  finishes.
  """
  fun name(): String => "integration/pipelined streaming"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [ (stallion.GET, "/stream1", _StreamingHandler, None)
        (stallion.GET, "/stream2", _PipelinedStreamHandler, None) ]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET /stream1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /stream2 HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "pipelined-ok")

// --- start_streaming() result handling test handlers ---

primitive \nodoc\ _StreamingAlreadyRespondedHandler is Handler
  """Responds, then tries to start streaming — tests AlreadyResponded error."""
  fun apply(ctx: Context ref) ? =>
    ctx.respond(stallion.StatusOK, "first response")
    ctx.start_streaming(stallion.StatusOK)?

primitive \nodoc\ _StreamingFallbackHandler is Handler
  """Starts streaming with fallback for ChunkedNotSupported."""
  fun apply(ctx: Context ref) ? =>
    match ctx.start_streaming(stallion.StatusOK)?
    | let sender: StreamSender tag =>
      _StreamingProducer(sender)
    | stallion.ChunkedNotSupported =>
      ctx.respond(stallion.StatusOK, "chunked-fallback")
    end

// --- start_streaming() result handling integration tests ---

class \nodoc\ iso _TestStreamingAlreadyResponded is UnitTest
  """
  Handler responds then calls start_streaming — error propagates, original
  response stands (no 500).
  """
  fun name(): String => "integration/streaming already responded"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _StreamingAlreadyRespondedHandler, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "first response")

class \nodoc\ iso _TestStreamingChunkedNotSupported is UnitTest
  """
  HTTP/1.0 request to a streaming handler — ChunkedNotSupported triggers
  fallback to ctx.respond().
  """
  fun name(): String => "integration/streaming chunked not supported"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    let router = _IntegrationHelpers.build_router(recover val
      [(stallion.GET, "/", _StreamingFallbackHandler, None)]
    end)
    _IntegrationHelpers.run_test(h, router,
      "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n",
      "chunked-fallback")
