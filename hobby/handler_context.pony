use "collections"
use stallion = "stallion"

class iso HandlerContext
  """
  Request context consumed by a handler factory to create a handler.

  Carries the HTTP request, route parameters, and request body. Created by
  `_Connection` and passed to the `HandlerFactory` lambda. The factory
  consumes the iso context — typically by passing it to a `RequestHandler`.

  Public fields are `val` (immutable, shareable). Internal fields are
  package-private and used by `RequestHandler` to communicate with the
  connection.
  """
  let request: stallion.Request val
  let params: Map[String, String] val
  let body: Array[U8] val
  let _conn: _ConnectionProtocol tag
  let _token: U64
  let _is_head: Bool

  new iso _create(request': stallion.Request val,
    params': Map[String, String] val, body': Array[U8] val,
    conn': _ConnectionProtocol tag, token': U64, is_head': Bool)
  =>
    request = request'
    params = params'
    body = body'
    _conn = conn'
    _token = token'
    _is_head = is_head'

  fun _get_conn(): _ConnectionProtocol tag => _conn
  fun _get_token(): U64 => _token
  fun _get_is_head(): Bool => _is_head
