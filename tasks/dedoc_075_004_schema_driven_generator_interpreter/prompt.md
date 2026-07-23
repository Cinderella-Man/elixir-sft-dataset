# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

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
