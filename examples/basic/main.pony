// in your code this `use` statement would be:
// use "hobby"
use "../../hobby"

actor Main
  """
  Basic hobby framework example.

  This example will demonstrate HTTP routing and request handling
  once those features are implemented.
  """
  new create(env: Env) =>
    env.out.print("Hobby framework - basic example")
    env.out.print("Coming soon: HTTP routing and handler examples")
