Implement the public `object/2` function. It takes a value generator `value_gen`
and a non-negative integer `max_length`, and produces a `StreamData` generator of
maps holding `0..max_length` entries. Each entry's key must be a **non-empty**
alphanumeric string (min length 1, max length 8) and each entry's value must be
drawn from `value_gen`. Build a generator of `{key, value}` tuples, generate a
list of such pairs with `max_length: max_length`, and turn that list into a map
with `Map.new/1` via `StreamData.map/2`. Because keys are drawn independently the
resulting map may contain fewer than `max_length` entries when keys collide, which
is always a valid object. Guard the function so it only accepts an integer
`max_length` that is `>= 0`. The returned value must be a `%StreamData{}` struct.

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
    # TODO
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