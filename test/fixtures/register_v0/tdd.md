# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule WTest do
  use ExUnit.Case
  test "go" do
    assert W.go() == :ok
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
