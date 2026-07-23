# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`go/0` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `go/0`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `go/0` missing

```elixir
defmodule W do
  # TODO: @spec
  def go, do: :ok
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
