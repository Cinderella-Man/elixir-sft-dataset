Write me an Elixir module called `JsonGenerators` that provides reusable `StreamData` generators for **recursive, JSON-shaped values**, intended for use with property-based testing via the `StreamData` and `ExUnitProperties` libraries.

Unlike flat domain-model generators, the interesting constraint here is **bounded recursion depth**: nested arrays and objects must never nest deeper than a caller-specified limit, and that bound must be guaranteed structurally (never by rejection/filtering).

Define the depth of a value as: a scalar (null, boolean, integer, string) has depth `0`; a container (array or object) has depth `1 + max(depth of its children)`, where an empty container has depth `1`.

I need these generators in the public API:

- `JsonGenerators.scalar()` — produces a JSON scalar: one of `nil`, a boolean, an integer, or an alphanumeric string (max 8 chars). Depth is always `0`.
- `JsonGenerators.array(element_gen, max_length)` — produces a list of `0..max_length` elements drawn from `element_gen`.
- `JsonGenerators.object(value_gen, max_length)` — produces a map with `0..max_length` entries, where each key is a **non-empty** alphanumeric string and each value is drawn from `value_gen`.
- `JsonGenerators.value(max_depth)` — produces an arbitrary JSON value (scalar, array, or object). When `max_depth <= 0` it always produces a scalar; otherwise it may produce scalars or containers whose children are drawn from `value(max_depth - 1)`. The generated value's depth must **always** be `<= max_depth`.

All depth and shape constraints must be enforced inside the generators themselves — consumers should never need to call `StreamData.filter/2`. Each generator must return a `%StreamData{}` struct so it composes with the standard `StreamData` combinators.

Give me the complete module in a single file. Use only `stream_data` as an external dependency, no others.