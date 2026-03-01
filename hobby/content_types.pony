use "collections"

primitive _ContentTypeDefaults
  """
  Build the default content-type map with 17 common file
  extensions.
  """
  fun apply(): Map[String, String] ref^ =>
    let m = Map[String, String](24)
    m("html") = "text/html"
    m("htm") = "text/html"
    m("css") = "text/css"
    m("js") = "text/javascript"
    m("json") = "application/json"
    m("xml") = "application/xml"
    m("txt") = "text/plain"
    m("png") = "image/png"
    m("jpg") = "image/jpeg"
    m("jpeg") = "image/jpeg"
    m("gif") = "image/gif"
    m("svg") = "image/svg+xml"
    m("ico") = "image/x-icon"
    m("woff") = "font/woff"
    m("woff2") = "font/woff2"
    m("pdf") = "application/pdf"
    m("wasm") = "application/wasm"
    m

class val ContentTypes
  """
  Map file extensions to MIME content types.

  Ships with 17 common defaults (html, css, js, json, xml, txt,
  png, jpg, jpeg, gif, svg, ico, woff, woff2, pdf, wasm, htm).
  Chain `add` calls to add custom mappings or override defaults --
  each call returns a new `ContentTypes` with the entry added:

  ```pony
  let types = hobby.ContentTypes
    .add("webp", "image/webp")
    .add("avif", "image/avif")
  hobby.ServeFiles(
    root where content_types = types)
  ```

  Lookups are case-insensitive -- both the default keys and
  user-provided keys are lowercased. Unknown extensions return
  `application/octet-stream`.
  """
  let _map: Map[String, String] val

  new val create() =>
    """
    Create a `ContentTypes` with the 17 standard defaults.
    """
    _map = recover val _ContentTypeDefaults() end

  new val _from_map(map: Map[String, String] val) =>
    """
    Create a `ContentTypes` from a pre-built map.
    """
    _map = map

  fun val add(
    ext: String,
    mime: String)
    : ContentTypes val
  =>
    """
    Return a new `ContentTypes` with the given mapping added. If
    `ext` already exists, the new MIME type replaces the previous
    one. The extension is lowercased before insertion so lookups
    are always case-insensitive.
    """
    let new_map =
      recover val
      let m = Map[String, String](_map.size() + 1)
      for (k, v) in _map.pairs() do
        m(k) = v
      end
      m(ext.lower()) = mime
      m
    end
    ContentTypes._from_map(new_map)

  fun apply(ext: String): String =>
    """
    Look up the MIME type for `ext`. Returns
    `application/octet-stream` when the extension is not in the
    map.
    """
    try
      _map(ext.lower())?
    else
      "application/octet-stream"
    end
