# Write the test harness

Module and original specification below. Produce the ExUnit harness that
verifies a correct implementation.

Hard requirements:
- Test module: `<Module>Test`, `use ExUnit.Case, async: false`.
- No `ExUnit.start()` (the evaluator owns startup).
- Self-contained single file: inline any fakes, clock Agents, and helpers.
- Full public API coverage plus the specification's edge cases.
- Compiles with zero warnings (`_`-prefix unused variables; float zero
  matches as `+0.0`/`-0.0`).

## Original specification

Write me an Elixir module called `SchemaGenerators` that turns a **declarative schema description** into a `StreamData` generator at runtime, for use with property-based testing via `StreamData` and `ExUnitProperties`.

Instead of hand-writing a fixed generator per type, I want one interpreter, `SchemaGenerators.from_schema/1`, that recursively walks a schema term and returns a `%StreamData{}` generator whose produced values conform to that schema. This lets tests describe the data they want as plain data.

`from_schema/1` must support exactly this schema grammar:

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

The interpreter must recurse so that nested schemas (e.g. a list of maps, a map with optional list-valued fields) produce correctly nested generators. All constraints come from the returned generator itself — consumers never filter. The result of `from_schema/1` must be a `%StreamData{}` struct that composes with the standard `StreamData` combinators.

Give me the complete module in a single file. Use only `stream_data` as an external dependency, no others.

## Module under test

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
