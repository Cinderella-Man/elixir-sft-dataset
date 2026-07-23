# Fill in the middle: implement the blanked property

Below is a module and its ExUnit test harness with the body of ONE `property` removed
(marked `# TODO`). The property's name states what it must verify. Implement just that one
property so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule W do
  def go, do: :ok
end
```

## Test harness — implement the `# TODO` property

```elixir
defmodule WTest do
  use ExUnit.Case
  test "go" do
    # TODO
  end
end
```
