use "collections"
use "pony_test"
use "time"
use "uri"
use stallion = "stallion"

primitive \nodoc\ _TestRequestHandlerList
  fun tests(test: PonyTest) =>
    test(_TestStartStreamingAfterRespond)
    test(_TestDoubleRespond)
    test(_TestSendChunkNotStreaming)
    test(_TestRespondWithHeaders)
    test(_TestStartStreamingHead)
    test(_TestStartStreamingHTTP10)

// --- Mock connection ---
actor \nodoc\ _MockConnection is _ConnectionProtocol
  """
  Mock connection that accepts all protocol messages as no-ops.
  """

  be _handler_respond(
    token: U64,
    status: stallion.Status,
    headers: (stallion.Headers val | None),
    body: ByteSeq)
  =>
    None

  be _handler_start_streaming(
    token: U64,
    status: stallion.Status,
    headers: (stallion.Headers val | None))
  =>
    None

  be _handler_send_chunk(token: U64, data: ByteSeq) => None
  be _handler_finish(token: U64) => None

actor \nodoc\ _CountingMockConnection is _ConnectionProtocol
  """
  Mock connection that counts protocol calls.
  """
  var _respond_count: USize = 0
  var _chunk_count: USize = 0
  var _finish_count: USize = 0

  be _handler_respond(
    token: U64,
    status: stallion.Status,
    headers: (stallion.Headers val | None),
    body: ByteSeq)
  =>
    _respond_count = _respond_count + 1

  be _handler_start_streaming(
    token: U64,
    status: stallion.Status,
    headers: (stallion.Headers val | None))
  =>
    None

  be _handler_send_chunk(token: U64, data: ByteSeq) =>
    _chunk_count = _chunk_count + 1

  be _handler_finish(token: U64) =>
    _finish_count = _finish_count + 1

  be check_respond_count(
    h: TestHelper,
    expected: USize)
  =>
    h.assert_eq[USize](expected, _respond_count)
    h.complete(true)

  be check_no_streaming(
    h: TestHelper,
    expected_respond: USize)
  =>
    h.assert_eq[USize](
      expected_respond,
      _respond_count,
      "respond count")
    h.assert_eq[USize](
      0,
      _chunk_count,
      "chunk count")
    h.assert_eq[USize](
      0,
      _finish_count,
      "finish count")
    h.complete(true)

// --- Helper ---
primitive \nodoc\ _MockRequest
  fun apply(): stallion.Request val =>
    let mock_uri = URI(None, None, "/", None, None)
    let mock_headers: stallion.Headers val =
      recover val stallion.Headers end
    let mock_cookies = stallion.ParseCookies("")
    stallion.Request(
      stallion.GET,
      mock_uri,
      stallion.HTTP11,
      mock_headers,
      mock_cookies)

primitive \nodoc\ _MockHandlerContext
  fun apply(
    conn: _ConnectionProtocol tag)
    : HandlerContext iso^
  =>
    let params: Map[String, String] val =
      recover val Map[String, String] end
    let body: Array[U8] val = recover val Array[U8] end
    recover iso
      HandlerContext._create(
        _MockRequest(),
        params,
        body,
        conn,
        1,
        false)
    end

primitive \nodoc\ _MockHTTP10Request
  fun apply(): stallion.Request val =>
    let mock_uri = URI(None, None, "/", None, None)
    let mock_headers: stallion.Headers val =
      recover val stallion.Headers end
    let mock_cookies = stallion.ParseCookies("")
    stallion.Request(
      stallion.GET,
      mock_uri,
      stallion.HTTP10,
      mock_headers,
      mock_cookies)

primitive \nodoc\ _MockHeadHandlerContext
  fun apply(
    conn: _ConnectionProtocol tag)
    : HandlerContext iso^
  =>
    let params: Map[String, String] val =
      recover val Map[String, String] end
    let body: Array[U8] val = recover val Array[U8] end
    recover iso
      HandlerContext._create(
        _MockRequest(),
        params,
        body,
        conn,
        1,
        true)
    end

primitive \nodoc\ _MockHTTP10HandlerContext
  fun apply(
    conn: _ConnectionProtocol tag)
    : HandlerContext iso^
  =>
    let params: Map[String, String] val =
      recover val Map[String, String] end
    let body: Array[U8] val = recover val Array[U8] end
    recover iso
      HandlerContext._create(
        _MockHTTP10Request(),
        params,
        body,
        conn,
        1,
        false)
    end

// --- Tests ---
class \nodoc\ iso _TestStartStreamingAfterRespond is UnitTest
  """
  start_streaming() returns BodyNotNeeded after respond() was called.
  """
  fun name(): String =>
    "request handler/start_streaming after respond"

  fun apply(h: TestHelper) =>
    let mock = _MockConnection
    let handler =
      RequestHandler(_MockHandlerContext(mock))
    handler.respond(stallion.StatusOK, "done")
    let result =
      handler.start_streaming(stallion.StatusOK)
    h.assert_true(result is BodyNotNeeded)

class \nodoc\ iso _TestDoubleRespond is UnitTest
  """
  Second respond() call is silently ignored.
  """
  fun name(): String => "request handler/double respond"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let mock = _CountingMockConnection
    let handler =
      RequestHandler(_MockHandlerContext(mock))
    handler.respond(stallion.StatusOK, "first")
    handler.respond(stallion.StatusOK, "second")
    mock.check_respond_count(h, 1)

class \nodoc\ iso _TestSendChunkNotStreaming is UnitTest
  """
  send_chunk() and finish() are no-ops when not streaming.
  """
  fun name(): String =>
    "request handler/send_chunk not streaming"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let mock = _CountingMockConnection
    let handler =
      RequestHandler(_MockHandlerContext(mock))
    handler.respond(stallion.StatusOK, "done")
    handler.send_chunk("ignored")
    handler.finish()
    mock.check_no_streaming(h, 1)

class \nodoc\ iso _TestRespondWithHeaders is UnitTest
  """
  respond_with_headers() sends once, second call is ignored.
  """
  fun name(): String =>
    "request handler/respond with headers"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let mock = _CountingMockConnection
    let handler =
      RequestHandler(_MockHandlerContext(mock))
    let headers: stallion.Headers val =
      recover val
        stallion.Headers .> set("X-Test", "value")
      end
    handler.respond_with_headers(
      stallion.StatusOK, headers, "body")
    handler.respond_with_headers(
      stallion.StatusOK, headers, "body2")
    mock.check_respond_count(h, 1)

class \nodoc\ iso _TestStartStreamingHead is UnitTest
  """
  start_streaming() returns BodyNotNeeded for HEAD requests.
  """
  fun name(): String =>
    "request handler/start_streaming HEAD"

  fun apply(h: TestHelper) =>
    h.long_test(10_000_000_000)
    let mock = _CountingMockConnection
    let handler =
      RequestHandler(_MockHeadHandlerContext(mock))
    let result =
      handler.start_streaming(stallion.StatusOK)
    h.assert_true(result is BodyNotNeeded)
    // HEAD path sends a headers-only respond
    mock.check_respond_count(h, 1)

class \nodoc\ iso _TestStartStreamingHTTP10 is UnitTest
  """
  start_streaming() returns ChunkedNotSupported for HTTP/1.0.
  """
  fun name(): String =>
    "request handler/start_streaming HTTP/1.0"

  fun apply(h: TestHelper) =>
    let mock = _MockConnection
    let handler =
      RequestHandler(_MockHTTP10HandlerContext(mock))
    let result =
      handler.start_streaming(stallion.StatusOK)
    h.assert_true(
      result is stallion.ChunkedNotSupported)
