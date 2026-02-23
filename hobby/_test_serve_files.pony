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
