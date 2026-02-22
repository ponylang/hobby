use "pony_test"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  fun tag tests(test: PonyTest) =>
    _TestRouterList.tests(test)
    _TestRouteGroupList.tests(test)
    _TestIntegrationList.tests(test)
