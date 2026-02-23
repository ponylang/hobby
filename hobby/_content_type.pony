primitive _ContentType
  """
  Map file extensions to MIME content types.

  Returns `application/octet-stream` for unrecognized extensions. The match
  is case-insensitive (extensions are lowercased before lookup).
  """
  fun apply(ext: String): String =>
    match ext.lower()
    | "html" | "htm" => "text/html"
    | "css" => "text/css"
    | "js" => "text/javascript"
    | "json" => "application/json"
    | "xml" => "application/xml"
    | "txt" => "text/plain"
    | "png" => "image/png"
    | "jpg" | "jpeg" => "image/jpeg"
    | "gif" => "image/gif"
    | "svg" => "image/svg+xml"
    | "ico" => "image/x-icon"
    | "woff" => "font/woff"
    | "woff2" => "font/woff2"
    | "pdf" => "application/pdf"
    | "wasm" => "application/wasm"
    else
      "application/octet-stream"
    end
