trait tag _FileTarget
  """

  Internal interface for `_FileStreamer` to send file chunks to.

  Replaces the public `StreamSender` interface for file streaming. The handler
  actor (`_ServeFilesHandler`) implements this and forwards chunks through
  `RequestHandler`.
  """

  be _file_chunk(data: Array[U8] val)
  be _file_done()
