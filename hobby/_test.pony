use "pony_test"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  fun tag tests(test: PonyTest) =>
    _TestRouterList.tests(test)
    _TestRouteGroupList.tests(test)
    _TestContentTypeList.tests(test)
    _TestHTTPDateList.tests(test)
    _TestETagList.tests(test)
    _TestRequestHandlerList.tests(test)
    _TestRequestInterceptorList.tests(test)
    _TestResponseInterceptorList.tests(test)
    _TestIntegrationList.tests(test)
    _TestServeFilesList.tests(test)
    _TestSignedCookieList.tests(test)
