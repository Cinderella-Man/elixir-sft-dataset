Implement the public `from_schema/1` function for the `SchemaGenerators` module.

`from_schema/1` is a small recursive interpreter: given a declarative schema term,
it returns a `%StreamData{}` generator whose produced values conform to that schema.
Every constraint must be baked into the returned generator so that consumers never
need to filter, and nested schemas must recurse so that composite schemas (e.g. a
list of maps, or a map with optional list-valued fields) yield correctly nested
generators. Use the `StreamData` module (aliased as `SD`) for all generators.

Implement it as a set of function clauses covering exactly this grammar:

- `:integer` — return `SD.integer()` (any integer).
- `{:integer, min, max}` — return `SD.integer(min..max)`. Guard that `min` and
  `max` are integers with `min <= max`.
- `:boolean` — return `SD.boolean()`.
- `:string` — return `SD.string(:alphanumeric)` (a possibly-empty alphanumeric string).
- `{:string, min_len, max_len}` — return `SD.string(:alphanumeric, min_length: min_len, max_length: max_len)`.
  Guard that `min_len` and `max_len` are integers with `min_len >= 0` and `min_len <= max_len`.
- `{:enum, values}` — return `SD.member_of(values)`. Guard that `values` is a non-empty list.
- `{:list, schema}` — return `SD.list_of(from_schema(schema))` (0 or more elements).
- `{:list, schema, opts}` — read `min = Keyword.get(opts, :min, 0)` and
  `max = Keyword.get(opts, :max, 10)`, then bind an integer length in `min..max` and
  generate a list of that exact length whose elements conform to `schema`. Guard that
  `opts` is a list.
- `{:map, schema_map}` — build a map of generators by recursing on each value schema,
  then return `SD.fixed_map(generators)` (a fixed-shape map with exactly the given keys).
  Guard that `schema_map` is a map.
- `{:optional, schema}` — return a generator that produces either `nil` or a value
  conforming to `schema` (use `SD.constant(nil)` and `SD.one_of/1`).
- `{:one_of, schemas}` — return `SD.one_of/1` over each schema mapped through
  `from_schema/1`. Guard that `schemas` is a non-empty list.

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
  # TODO
end
```