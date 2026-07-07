Implement the public `value/1` function. It produces a `StreamData` generator for
an arbitrary JSON value whose depth is structurally guaranteed to be `<= max_depth`
— the bound must come from the shape of the generator, never from filtering.

Write it as two guarded clauses over the integer `max_depth`:

- When `max_depth <= 0`, the generator must always yield a scalar. Delegate to
  `scalar/0`.
- When `max_depth > 0`, first build a `child` generator for the next level down by
  recursing with `value(max_depth - 1)`. Then return `SD.one_of/1` over three
  alternatives: a `scalar()`, an `array(child, 5)`, and an `object(child, 5)`. Because
  every container's children are drawn from `value(max_depth - 1)`, induction
  guarantees the depth invariant holds.

The function must return a `%StreamData{}` struct so it composes with the standard
`StreamData` combinators.

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
    # TODO
  end
end
```