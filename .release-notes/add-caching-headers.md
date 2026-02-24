## Add caching headers for ServeFiles

`ServeFiles` now includes caching headers on all responses:

- **ETag**: Weak ETag computed from file metadata (`W/"<inode>-<size>-<mtime>"`).
- **Last-Modified**: RFC 7231 HTTP-date from the file's modification time.
- **Cache-Control**: Defaults to `"public, max-age=3600"`. Customizable via the new `cache_control` constructor parameter, or pass `None` to omit.

Conditional requests are supported per RFC 7232 — clients can send `If-None-Match` or `If-Modified-Since` headers to receive 304 Not Modified when the file hasn't changed, avoiding re-downloading unchanged files.

```pony
// Default: 1-hour public caching
hobby.ServeFiles(root)

// Custom cache policy
hobby.ServeFiles(root where cache_control = "private, max-age=600")

// No Cache-Control header
hobby.ServeFiles(root where cache_control = None)
```
