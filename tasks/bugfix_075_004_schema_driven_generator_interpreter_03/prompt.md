# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

I've got a pile of property tests where every new data shape means hand-writing yet another generator, and I'd like to stop doing that. Can you build me an Elixir module called `SchemaGenerators` that takes a **declarative schema description** and turns it into a `StreamData` generator at runtime? The consumers are property-based tests written with `StreamData` and `ExUnitProperties`.

The idea is one interpreter instead of one generator per type: `SchemaGenerators.from_schema/1` walks a schema term recursively and hands back a `%StreamData{}` generator whose produced values conform to that schema. That way a test can just describe the data it wants as plain data.

Here's the exact grammar I need `from_schema/1` to handle — nothing more, nothing less:

- `:integer` — any integer.
- `{:integer, min, max}` — an integer in `min..max` (require `min <= max`).
- `:boolean` — a boolean.
- `:string` — an alphanumeric string (possibly empty).
- `{:string, min_len, max_len}` — an alphanumeric string whose length is in `min_len..max_len`.
- `{:enum, values}` — one of the given non-empty list of literal `values`.
- `{:list, schema}` — a list (0 or more elements) of values conforming to `schema`.
- `{:list, schema, opts}` — a list whose length is in `Keyword.get(opts, :min, 0)..Keyword.get(opts, :max, 10)`, of values conforming to `schema`.
- `{:map, schema_map}` — a map with exactly the keys of `schema_map`, where each value conforms to that key's schema (a fixed-shape map).
- `{:optional, schema}` — either `nil` or a value conforming to `schema`.
- `{:one_of, schemas}` — a value conforming to one of the given non-empty list of `schemas`.

The recursion matters to me: nested schemas — say a list of maps, or a map with optional list-valued fields — have to come out as correctly nested generators. And every constraint needs to live in the returned generator itself; I don't want callers filtering anything downstream. Whatever `from_schema/1` returns has to be a `%StreamData{}` struct so it composes with the standard `StreamData` combinators.

Please send the whole module as a single file, and keep `stream_data` as the only external dependency — no others.

## The buggy module

```elixir
defmodule SchemaGenerators do
  @moduledoc """
  Turns a declarative schema term into a `StreamData` generator at runtime, for
  use with property-based testing via `StreamData` and `ExUnitProperties`.

  Rather than hand-writing one generator per type, `from_schema/1` is a small
  recursive interpreter: it walks a schema value and returns a `%StreamData{}`
  generator whose outputs conform to that schema. Nested schemas produce nested
  generators, and every constraint is baked into the returned generator so
  consumers never filter.

  ## Schema grammar

      :integer
      {:integer, min, max}
      :boolean
      :string
      {:string, min_len, max_len}
      {:enum, [value, ...]}
      {:list, schema}
      {:list, schema, opts}          # opts: [min: n, max: n]
      {:map, %{key => schema}}
      {:optional, schema}
      {:one_of, [schema, ...]}

  ## Usage

      use ExUnitProperties

      property "conforms to the schema" do
        gen = SchemaGenerators.from_schema({:map, %{id: {:integer, 1, 100}}})

        check all value <- gen do
          assert value.id in 1..100
        end
      end
  """

  alias StreamData, as: SD

  @doc """
  Interprets `schema` and returns a `StreamData` generator producing conforming
  values. Recurses through nested schemas.
  """
  @spec from_schema(term()) :: StreamData.t(term())
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
    max = Keyword.get(opts, :max, 11)

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

## Failing test report

```
1 of 19 test(s) failed:

  * property boundary bounds and defaults {:list, schema, opts} defaults length bounds to 0..10
      
      
      Expected truthy, got false
      code: assert Enum.all?(lengths, fn len -> len >= 0 and len <= 10 end)
      arguments:
      
               # 1
               [0, 6, 6, 2, 8, 10, 9, 11, 1, 2, 3, 6, 7, 4, 9, 2, 6, 4, 5, 8, 2, 9, 1, 6, 6, 6, 4, 7, 4, 7, 3, 11, 7, 9, 0, 0, 1, 4, 11, 3, 7, 0, 3, 5, 3, 11, 7, 9, 4, 5, 11, 3, 1, 0, 5, 6, 7, 0, 7, 1, 3, 4, 2, 8, 9, 11, 9, 4, 7, 6, 9, 8, 6, 0, 9, 3, 1, 0, 5, 6, 11, 11, 0, 11, 3, 7, 9, 9, 3, 2, 6, 2, 10, 9, 11, 8, 10, 1, 6, 5, 6, 1, 11, 11, 3, 8, 8, 8, 10, 9, 11, 2, 0, 1, 1, 5, 6
```
