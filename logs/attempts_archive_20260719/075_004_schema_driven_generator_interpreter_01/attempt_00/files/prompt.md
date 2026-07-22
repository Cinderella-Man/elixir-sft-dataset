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