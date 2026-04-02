use "files"

actor _FileStreamer
  """

  Read a file in chunks and send them to a `_FileTarget`.

  Reads 64 KB chunks using self-directed `_read_next()` messages so the Pony
  scheduler can interleave other actors between reads. When the read returns
  an empty array (EOF), calls `_file_done()` and disposes the file. On a read
  error mid-stream, finishes immediately — the client receives whatever was
  sent up to that point.

  Supports backpressure via `pause()` and `resume()`. When paused, the read
  loop stops sending chunks. `resume()` restarts the loop from where it left
  off. The connection's `throttled()`/`unthrottled()` signals drive this —
  see `_ServeFilesHandler` for the wiring.
  """

  let _file: File
  let _target: _FileTarget tag
  var _disposed: Bool = false
  var _paused: Bool = false

  new create(file: File iso, target: _FileTarget tag) =>
    _file = consume file
    _target = target
    _read_next()

  be _read_next() =>
    if _disposed then return end
    if _paused then return end
    let chunk = _file.read(65536)
    if chunk.size() > 0 then
      _target._file_chunk(consume chunk)
      _read_next()
    else
      // EOF (0 bytes, errno is FileEOF) or read error — either way, finish.
      _target._file_done()
      _file.dispose()
    end

  be pause() =>
    """
    Pause the read loop. No further chunks are sent until `resume()`.
    """
    _paused = true

  be resume() =>
    """
    Resume the read loop after a `pause()`. No-op if not paused.
    """
    if _paused then
      _paused = false
      if not _disposed then
        _read_next()
      end
    end

  be dispose() =>
    if not _disposed then
      _disposed = true
      _file.dispose()
    end
