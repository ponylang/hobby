use "pony_test"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  fun tag tests(test: PonyTest) =>
    _TestRouterList.tests(test)
    _TestRouteGroupList.tests(test)
    _TestContentTypeList.tests(test)
    _TestHttpDateList.tests(test)
    _TestETagList.tests(test)
    _TestRequestHandlerList.tests(test)
    _TestIntegrationList.tests(test)
    _TestServeFilesList.tests(test)
    _TestSignedCookieList.tests(test)
    _TestSessionIdList.tests(test)
    _TestSessionDataList.tests(test)
    _TestSessionEditorList.tests(test)
    _TestSessionStoreList.tests(test)
    _TestSessionConfigList.tests(test)
    _TestSessionLoaderList.tests(test)
    _TestSessionCookieWriterList.tests(test)
