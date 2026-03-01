use "files"

actor _FileStreamer
  """
  Read a file in chunks and send them via a `StreamSender`.

  Reads 64 KB chunks using self-directed `_read_next()` messages
  so the Pony scheduler can interleave other actors between reads.
  When the read returns an empty array (EOF), calls `finish()` and
  disposes the file. On a read error mid-stream, finishes
  immediately -- the client receives whatever was sent up to that
  point.
  """
  let _file: File
  let _sender: StreamSender tag

  new create(file: File iso, sender: StreamSender tag) =>
    _file = consume file
    _sender = sender
    _read_next()

  be _read_next() =>
    let chunk = _file.read(65536)
    if chunk.size() > 0 then
      _sender.send_chunk(consume chunk)
      _read_next()
    else
      // EOF (0 bytes, errno is FileEOF) or read error --
      // either way, finish.
      _sender.finish()
      _file.dispose()
    end
