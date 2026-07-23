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
