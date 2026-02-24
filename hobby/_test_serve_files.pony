use "pony_test"
use "files"
use stallion = "stallion"
use lori = "lori"

primitive \nodoc\ _TestServeFilesList
  fun tests(test: PonyTest) =>
    test(_TestServeFilesSmallFile)
    test(_TestServeFilesContentType)
    test(_TestServeFilesLargeFile)
    test(_TestServeFilesMissing404)
    test(_TestServeFilesTraversal404)
    test(_TestServeFilesDirectory404)
    test(_TestServeFilesLargeFileHTTP10)
    test(_TestServeFilesHeadSmallFile)
    test(_TestServeFilesHeadLargeFile)
    test(_TestServeFilesCacheHeadersPresent)
    test(_TestServeFilesETag304)
    test(_TestServeFilesIfModifiedSince304)
    test(_TestServeFilesETagMismatch200)
    test(_TestServeFilesHeadCacheHeaders)
    test(_TestServeFilesHead304)
    test(_TestServeFilesCacheControlCustom)
    test(_TestServeFilesCacheControlDisabled)
    test(_TestServeFilesLargeFileCacheHeaders)
    test(_TestServeFilesLargeFileETag304)
    test(_TestServeFilesETagPrecedence)

// --- Test setup ---

primitive \nodoc\ _ServeFilesTestSetup
  """
  Create a temporary directory with test files for ServeFiles integration
  tests. Idempotent — safe to call multiple times.
  """
  fun apply(env: Env): FilePath ? =>
    let file_auth = FileAuth(env.root)
    let root = FilePath(file_auth, "/tmp/hobby-test-serve")
    root.mkdir()

    // Small text file
    _write_file(root, "hello.txt", "Hello from test file")?

    // CSS file for content-type testing
    _write_file(root, "style.css", "body { color: red; }")?

    // Large file for streaming tests (2 KB, exceeds chunk_threshold=1)
    let large_content = recover val
      let s = String(2048)
      s.append("LARGE_FILE_MARKER:")
      while s.size() < 2048 do
        s.push('x')
      end
      s
    end
    _write_file(root, "large.txt", large_content)?

    // Subdirectory for directory test
    FilePath.from(root, "subdir")?.mkdir()

    root

  fun _write_file(root: FilePath, name: String, content: String) ? =>
    let path = FilePath.from(root, name)?
    let file = File(path)
    file.set_length(0)
    file.write(content)
    file.dispose()

// --- Integration tests ---

class \nodoc\ iso _TestServeFilesSmallFile is UnitTest
  """Small file served with correct Content-Type and body."""
  fun name(): String => "integration/serve-files/small file"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "Hello from test file")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesContentType is UnitTest
  """Content-Type header matches file extension."""
  fun name(): String => "integration/serve-files/content type"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/style.css HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "text/css")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesLargeFile is UnitTest
  """Large file streamed with chunked transfer encoding."""
  fun name(): String => "integration/serve-files/large file streaming"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let handler = ServeFiles(root where chunk_threshold = 1)
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", handler, None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/large.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "LARGE_FILE_MARKER:")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesMissing404 is UnitTest
  """Missing file returns 404."""
  fun name(): String => "integration/serve-files/missing file 404"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/nonexistent.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "Not Found")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesTraversal404 is UnitTest
  """Path traversal attempt returns 404."""
  fun name(): String => "integration/serve-files/path traversal 404"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/sub/../../etc/passwd HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "Not Found")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesDirectory404 is UnitTest
  """Requesting a directory returns 404."""
  fun name(): String => "integration/serve-files/directory 404"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/subdir HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "Not Found")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesLargeFileHTTP10 is UnitTest
  """HTTP/1.0 client requesting a large file gets 505."""
  fun name(): String => "integration/serve-files/large file HTTP 1.0 505"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let handler = ServeFiles(root where chunk_threshold = 1)
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", handler, None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/large.txt HTTP/1.0\r\nHost: localhost\r\n\r\n",
        "HTTP Version Not Supported")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesHeadSmallFile is UnitTest
  """HEAD for small file: Content-Length header present, body absent."""
  fun name(): String => "integration/serve-files/HEAD small file"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      // Headers go through stallion.Headers which lowercases names.
      _HeadIntegrationHelpers.run_head_test(h, router,
        "HEAD /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "content-length: 20", "Hello from test file")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesHeadLargeFile is UnitTest
  """HEAD for large file: Content-Length from stat, body absent."""
  fun name(): String => "integration/serve-files/HEAD large file"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let handler = ServeFiles(root where chunk_threshold = 1)
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", handler, None)]
      end)
      // Headers go through stallion.Headers which lowercases names.
      _HeadIntegrationHelpers.run_head_test(h, router,
        "HEAD /static/large.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "content-length: 2048", "LARGE_FILE_MARKER:")
    else
      h.fail("test setup failed")
    end

// --- Cache header helpers ---

primitive \nodoc\ _ServeFilesTestETag
  """Compute the expected ETag for a test file."""
  fun apply(root: FilePath, name': String): String ? =>
    let path = FilePath.from(root, name')?
    let info = FileInfo(path)?
    (let mod_secs, _) = info.modified_time
    _ETag(info.inode, info.size, mod_secs)

  fun last_modified(root: FilePath, name': String): String ? =>
    let path = FilePath.from(root, name')?
    let info = FileInfo(path)?
    (let mod_secs, _) = info.modified_time
    _HttpDate(mod_secs)

// --- Cache header integration tests ---

class \nodoc\ iso _TestServeFilesCacheHeadersPresent is UnitTest
  """GET response includes ETag header."""
  fun name(): String => "integration/serve-files/cache headers present"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let etag = _ServeFilesTestETag(root, "hello.txt")?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      // stallion.Headers lowercases header names
      _IntegrationHelpers.run_test(h, router,
        "GET /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "etag: " + etag)
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesETag304 is UnitTest
  """GET with matching If-None-Match returns 304."""
  fun name(): String => "integration/serve-files/ETag 304"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let etag = _ServeFilesTestETag(root, "hello.txt")?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n" +
          "If-None-Match: " + etag + "\r\n\r\n",
        "304 Not Modified")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesIfModifiedSince304 is UnitTest
  """GET with matching If-Modified-Since returns 304."""
  fun name(): String => "integration/serve-files/If-Modified-Since 304"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let last_mod = _ServeFilesTestETag.last_modified(root, "hello.txt")?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n" +
          "If-Modified-Since: " + last_mod + "\r\n\r\n",
        "304 Not Modified")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesETagMismatch200 is UnitTest
  """GET with non-matching If-None-Match returns 200 with body."""
  fun name(): String => "integration/serve-files/ETag mismatch 200"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n" +
          "If-None-Match: W/\"0-0-0\"\r\n\r\n",
        "Hello from test file")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesHeadCacheHeaders is UnitTest
  """HEAD response includes ETag header, body absent."""
  fun name(): String => "integration/serve-files/HEAD cache headers"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let etag = _ServeFilesTestETag(root, "hello.txt")?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _HeadIntegrationHelpers.run_head_test(h, router,
        "HEAD /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "etag: " + etag, "Hello from test file")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesHead304 is UnitTest
  """HEAD with matching If-None-Match returns 304."""
  fun name(): String => "integration/serve-files/HEAD ETag 304"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let etag = _ServeFilesTestETag(root, "hello.txt")?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "HEAD /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n" +
          "If-None-Match: " + etag + "\r\n\r\n",
        "304 Not Modified")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesCacheControlCustom is UnitTest
  """Custom cache_control value appears in response."""
  fun name(): String => "integration/serve-files/custom cache-control"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let handler = ServeFiles(root
        where cache_control = "private, max-age=600")
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", handler, None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "cache-control: private, max-age=600")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesCacheControlDisabled is UnitTest
  """cache_control = None omits Cache-Control header."""
  fun name(): String => "integration/serve-files/cache-control disabled"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let handler = ServeFiles(root where cache_control = None)
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", handler, None)]
      end)
      _ServeFilesCacheControlDisabledHelper.run_test(h, router,
        "GET /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "Hello from test file", "cache-control:")
    else
      h.fail("test setup failed")
    end

primitive \nodoc\ _ServeFilesCacheControlDisabledHelper
  """
  Run a test that checks for a required string AND verifies a forbidden
  string is absent.
  """
  fun run_test(h: TestHelper, router: _Router val,
    request: String, expected: String, forbidden: String)
  =>
    h.long_test(5_000_000_000)
    let host = _TestHost()
    let config = stallion.ServerConfig(host, "0")
    let auth = lori.TCPListenAuth(h.env.root)
    let connect_auth = lori.TCPConnectAuth(h.env.root)
    _TestIntegrationListener(auth, config, router, h,
      {(h': TestHelper, port: String,
        listener: _TestIntegrationListener) =>
        _TestNoCacheControlClient(connect_auth, host, port, h',
          request, expected, forbidden, listener)
      })

actor \nodoc\ _TestNoCacheControlClient is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """
  TCP client that checks a required string is present and a forbidden
  string is absent.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String
  let _expected: String
  let _forbidden: String
  let _listener: _TestIntegrationListener
  var _response: String iso = recover iso String end

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    h: TestHelper, request: String, expected: String, forbidden: String,
    listener: _TestIntegrationListener)
  =>
    _h = h
    _request = request
    _expected = expected
    _forbidden = forbidden
    _listener = listener
    _tcp_connection = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let response_str: String val = _response.clone()
    if response_str.contains(_expected) then
      _h.assert_false(response_str.contains(_forbidden),
        "Response must not contain: " + _forbidden)
      _tcp_connection.close()
      _listener.dispose()
      _h.complete(true)
    end

  fun ref _on_closed() => None

  fun ref _on_connection_failure() =>
    _h.fail("connection failed")
    _listener.dispose()
    _h.complete(false)

class \nodoc\ iso _TestServeFilesLargeFileCacheHeaders is UnitTest
  """Large file streaming response includes ETag header."""
  fun name(): String => "integration/serve-files/large file cache headers"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let etag = _ServeFilesTestETag(root, "large.txt")?
      let handler = ServeFiles(root where chunk_threshold = 1)
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", handler, None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/large.txt HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "etag: " + etag)
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesLargeFileETag304 is UnitTest
  """
  Large file with matching If-None-Match returns 304 (conditional check
  happens before size branch).
  """
  fun name(): String => "integration/serve-files/large file ETag 304"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let etag = _ServeFilesTestETag(root, "large.txt")?
      let handler = ServeFiles(root where chunk_threshold = 1)
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", handler, None)]
      end)
      _IntegrationHelpers.run_test(h, router,
        "GET /static/large.txt HTTP/1.1\r\nHost: localhost\r\n" +
          "If-None-Match: " + etag + "\r\n\r\n",
        "304 Not Modified")
    else
      h.fail("test setup failed")
    end

class \nodoc\ iso _TestServeFilesETagPrecedence is UnitTest
  """
  If-None-Match takes precedence over If-Modified-Since per RFC 7232 section 3.
  Matching ETag + non-matching If-Modified-Since still returns 304.
  """
  fun name(): String => "integration/serve-files/ETag precedence"

  fun label(): String => "integration"

  fun apply(h: TestHelper) =>
    try
      let root = _ServeFilesTestSetup(h.env)?
      let etag = _ServeFilesTestETag(root, "hello.txt")?
      let router = _IntegrationHelpers.build_router(recover val
        [(stallion.GET, "/static/*filepath", ServeFiles(root), None)]
      end)
      // Matching ETag but non-matching If-Modified-Since
      _IntegrationHelpers.run_test(h, router,
        "GET /static/hello.txt HTTP/1.1\r\nHost: localhost\r\n" +
          "If-None-Match: " + etag + "\r\n" +
          "If-Modified-Since: Thu, 01 Jan 1970 00:00:00 GMT\r\n\r\n",
        "304 Not Modified")
    else
      h.fail("test setup failed")
    end
