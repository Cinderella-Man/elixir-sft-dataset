# Fix the failing module

I asked for the following:

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

Here is my current implementation, but it is failing tests:

```elixir
defmodule JsonGenerators do
  @moduledoc """
  Reusable `StreamData` generators for recursive, JSON-shaped values, intended
  for use with property-based testing via `StreamData` and `ExUnitProperties`.

  The distinguishing feature of these generators is **structurally-bounded
  recursion depth**: `value/1` never produces a value that nests deeper than the
  requested limit, and that guarantee comes from the shape of the generator
  itself — never from rejection-filtering.

  Depth convention:

    * a scalar (`nil`, boolean, integer, string) has depth `0`
    * a container (list/map) has depth `1 + max(child depths)`; an empty
      container has depth `1`

  ## Usage

      use ExUnitProperties

      property "bounded json never nests too deep" do
        check all value <- JsonGenerators.value(3) do
          assert depth(value) <= 3
        end
      end

  All generators return `%StreamData{}` structs and compose with the standard
  `StreamData` combinator API.
  """

  # Qualify every call explicitly rather than bulk-importing StreamData: a bare
  # `import StreamData` pulls in dozens of functions whose arities can clash with
  # auto-imported Kernel functions.
  alias StreamData, as: SD

  @doc """
  Produces a JSON scalar: one of `nil`, a boolean, an integer, or an
  alphanumeric string of at most 8 characters. Always depth `0`.
  """
  @spec scalar() :: StreamData.t(term())
  def scalar do
    SD.one_of([
      SD.constant(nil),
      SD.boolean(),
      SD.integer(),
      SD.string(:alphanumeric, max_length: 8)
    ])
  end

  @doc """
  Produces a list of `0..max_length` elements drawn from `element_gen`.
  """
  @spec array(StreamData.t(a), non_neg_integer()) :: StreamData.t([a]) when a: term()
  def array(element_gen, max_length) when is_integer(max_length) and max_length >= 0 do
    SD.list_of(element_gen, max_length: max_length)
  end

  @doc """
  Produces a map of `0..max_length` entries where every key is a non-empty
  alphanumeric string and every value is drawn from `value_gen`.

  Keys are drawn independently, so the final map may contain fewer than
  `max_length` entries when keys collide — this is always a valid object.
  """
  @spec object(StreamData.t(a), non_neg_integer()) :: StreamData.t(%{optional(String.t()) => a})
        when a: term()
  def object(value_gen, max_length) when is_integer(max_length) and max_length >= 0 do
    key = SD.string(:alphanumeric, min_length: 1, max_length: 8)
    pair = SD.tuple({key, value_gen})

    SD.map(SD.list_of(pair, max_length: max_length), &Map.new/1)
  end

  @doc """
  Produces an arbitrary JSON value whose depth is guaranteed `<= max_depth`.

  For `max_depth <= 0` this always yields a scalar. For a positive depth it may
  yield a scalar, or a container whose children are drawn from
  `value(max_depth - 1)` — so by induction the depth invariant always holds.
  """
  @spec value(integer()) :: StreamData.t(term())
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

The failure report:

```
Tests failed (2 failed, 0 errors):
  - test array/2 attains exactly max_length elements across seeded samples (JsonGeneratorsTest): 

Assertion with == failed
code:  assert Enum.max(lengths) == 5
left:  4
right: 5

  - test object/2 attains exactly max_length entries across seeded samples (JsonGeneratorsTest): 

Assertion with == failed
code:  assert Enum.max(sizes) == 5
left:  4
right: 5

```

Find the bug and give me the corrected complete module in a single file.
<!-- minted from logs/attempts/075_002_recursive_json_value_generators_with_bounded_depth_01_audit/attempt_0 -->
