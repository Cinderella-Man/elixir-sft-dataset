# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule JsonGenerators do
  # Qualify every call explicitly rather than bulk-importing StreamData: a bare
  # `import StreamData` pulls in dozens of functions whose arities can clash with
  # auto-imported Kernel functions.
  alias StreamData, as: SD

  def scalar do
    SD.one_of([
      SD.constant(nil),
      SD.boolean(),
      SD.integer(),
      SD.string(:alphanumeric, max_length: 8)
    ])
  end

  def array(element_gen, max_length) when is_integer(max_length) and max_length >= 0 do
    SD.list_of(element_gen, max_length: max_length)
  end

  def object(value_gen, max_length) when is_integer(max_length) and max_length >= 0 do
    key = SD.string(:alphanumeric, min_length: 1, max_length: 8)
    pair = SD.tuple({key, value_gen})

    SD.map(SD.list_of(pair, max_length: max_length), &Map.new/1)
  end

  def value(max_depth) when is_integer(max_depth) and max_depth <= 0 do
    scalar()
  end

  def value(max_depth) when is_integer(max_depth) and max_depth > 0 do
    child = value(max_depth - 1)

    SD.one_of([
      scalar(),
      array(child, 5),
      object(child, 5)
    ])
  end
end
```
