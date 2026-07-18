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
defmodule SchemaGenerators do
  alias StreamData, as: SD

  def from_schema(:integer), do: SD.integer()

  def from_schema(:boolean), do: SD.boolean()

  def from_schema(:string), do: SD.string(:alphanumeric)

  def from_schema({:integer, min, max})
      when is_integer(min) and is_integer(max) and min <= max do
    SD.integer(min..max)
  end

  def from_schema({:string, min_len, max_len})
      when is_integer(min_len) and is_integer(max_len) and min_len >= 0 and min_len <= max_len do
    SD.string(:alphanumeric, min_length: min_len, max_length: max_len)
  end

  def from_schema({:enum, values}) when is_list(values) and values != [] do
    SD.member_of(values)
  end

  def from_schema({:list, inner}) do
    SD.list_of(from_schema(inner))
  end

  def from_schema({:list, inner, opts}) when is_list(opts) do
    min = Keyword.get(opts, :min, 0)
    max = Keyword.get(opts, :max, 10)

    SD.bind(SD.integer(min..max), fn len ->
      SD.list_of(from_schema(inner), length: len)
    end)
  end

  def from_schema({:map, schema_map}) when is_map(schema_map) do
    generators = Map.new(schema_map, fn {key, schema} -> {key, from_schema(schema)} end)
    SD.fixed_map(generators)
  end

  def from_schema({:optional, inner}) do
    SD.one_of([SD.constant(nil), from_schema(inner)])
  end

  def from_schema({:one_of, schemas}) when is_list(schemas) and schemas != [] do
    SD.one_of(Enum.map(schemas, &from_schema/1))
  end
end
```
