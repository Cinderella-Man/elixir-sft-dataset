# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Build a widget that frobnicates.

## The buggy module

```elixir
defmodule W do
  def go, do: :ok
end
```

## Failing test report

```
1 of 2 test(s) failed:

  * test go
      boom
```
