# Task: implement `SchemaGenerators.from_schema/1`

Implement the public `from_schema/1` function. It is a small recursive interpreter
that walks a declarative schema term and returns a `%StreamData{}` generator whose
produced values conform to that schema. Use `alias StreamData, as: SD`. Every
constraint must be baked into the returned generator so that consumers never have to
filter, and nested schemas must recurse so that nested generators compose correctly.

Support exactly this schema grammar, one clause at a time:

- `:integer` — any integer, via `SD.integer()`.
- `{:integer, min, max}` — an integer in `min..max`, via `SD.integer(min..max)`. Guard
  that `min` and `max` are integers with `min <= max`.
- `:boolean` — a boolean, via `SD.boolean()`.
- `:string` — a possibly-empty alphanumeric string, via `SD.string(:alphanumeric)`.
- `{:string, min_len, max_len}` — an alphanumeric string whose length is in
  `min_len..max_len`, via `SD.string(:alphanumeric, min_length: min_len, max_length: max_len)`.
  Guard that both are integers with `min_len >= 0` and `min_len <= max_len`.
- `{:enum, values}` — one of a non-empty list of literal `values`, via `SD.member_of(values)`.
  Guard that `values` is a non-empty list.
- `{:list, schema}` — a list (0 or more elements) of values conforming to `schema`, via
  `SD.list_of/1` applied to the recursively-built inner generator.
- `{:list, schema, opts}` — a list whose length is in
  `Keyword.get(opts, :min, 0)..Keyword.get(opts, :max, 10)`, of values conforming to
  `schema`. Use `SD.bind/2` over `SD.integer(min..max)` to pick a length, then
  `SD.list_of(inner, length: len)`. Guard that `opts` is a list.
- `{:map, schema_map}` — a fixed-shape map with exactly the keys of `schema_map`, where
  each value conforms to that key's schema. Build a map of per-key generators
  (recursing on each value schema) and pass it to `SD.fixed_map/1`. Guard that
  `schema_map` is a map.
- `{:optional, schema}` — either `nil` or a value conforming to `schema`, via
  `SD.one_of([SD.constant(nil), inner])`.
- `{:one_of, schemas}` — a value conforming to one of a non-empty list of `schemas`, via
  `SD.one_of/1` over the recursively-built generators. Guard that `schemas` is a
  non-empty list.

The result must be a `%StreamData{}` struct that composes with the standard
`StreamData` combinators.

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
  def from_schema(schema) do
    # TODO
  end
end
```