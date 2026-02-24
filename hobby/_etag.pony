primitive _ETag
  """
  Compute and match weak ETags from file metadata.

  ETags use the weak format `W/"<inode>-<size>-<mtime_secs>"`, matching the
  approach used by nginx and Apache. No file content hashing — computing a
  hash would defeat caching for large files.

  On Windows, `FileInfo.inode` is always 0, reducing collision resistance to
  size+mtime only. This is a known limitation.
  """
  fun apply(inode: U64, size: USize, mtime: I64): String =>
    """Compute a weak ETag from file metadata."""
    recover val
      let s = String
      s.append("W/\"")
      s.append(inode.string())
      s.push('-')
      s.append(size.string())
      s.push('-')
      s.append(mtime.string())
      s.push('"')
      s
    end

  fun matches(if_none_match: String, server_etag: String): Bool =>
    """
    Check if an `If-None-Match` header value matches the server's ETag.

    Uses weak comparison per RFC 7232 section 2.3.2: strip the `W/` prefix and
    compare opaque-tags. Handles the `*` wildcard and comma-separated lists.
    """
    let trimmed = if_none_match.clone().>strip()
    if trimmed == "*" then return true end

    let server_opaque = _opaque_tag(server_etag)

    // Split by comma and check each entry
    for entry in trimmed.split(",").values() do
      let candidate: String val = entry.clone().>strip()
      if candidate.size() > 0 then
        if _opaque_tag(candidate) == server_opaque then
          return true
        end
      end
    end
    false

  fun _opaque_tag(etag: String): String =>
    """
    Extract the opaque-tag from an ETag value.

    Strips the optional `W/` weak indicator prefix (case-insensitive), then
    strips surrounding double quotes.
    """
    var s = etag.clone().>strip()
    // Strip W/ prefix (case-insensitive)
    if (s.size() >= 2) and
      (s.compare_sub("W/", 2, 0, 0, true) is Equal)
    then
      s = s.substring(2)
    end
    // Strip surrounding quotes
    if (s.size() >= 2) and
      (try s(0)? == '"' else false end) and
      (try s(s.size() - 1)? == '"' else false end)
    then
      s = s.substring(1, s.size().isize() - 1)
    end
    s
