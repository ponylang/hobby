## Add extensible content-type mapping

`ServeFiles` now accepts a `content_types` parameter for adding custom file extension to MIME type mappings or overriding the built-in defaults. The new `ContentTypes` class ships with 17 common defaults and supports user extensions by chaining `.add()` calls:

```pony
let types = hobby.ContentTypes
  .add("webp", "image/webp")
  .add("avif", "image/avif")
hobby.ServeFiles(root where content_types = types)
```

Without a `content_types` argument, `ServeFiles` behaves exactly as before — unrecognized extensions still produce `application/octet-stream`. Lookups are case-insensitive.
