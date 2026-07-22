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

  @max_key_length 8
  @container_max_length 5

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
      SD.string(:alphanumeric, max_length: @max_key_length)
    ])
  end

  @doc """
  Produces a list of `0..max_length` elements drawn from `element_gen`.

  The length is drawn uniformly from `0..max_length` and then fixed, so every
  admissible length — including the bound itself — is reachable independently of
  the current generation size.
  """
  @spec array(StreamData.t(a), non_neg_integer()) :: StreamData.t([a]) when a: term()
  def array(element_gen, max_length) when is_integer(max_length) and max_length >= 0 do
    SD.bind(SD.integer(0..max_length), fn len ->
      SD.list_of(element_gen, length: len)
    end)
  end

  @doc """
  Produces a map of `0..max_length` entries where every key is a non-empty
  alphanumeric string and every value is drawn from `value_gen`.

  Keys are drawn as a duplicate-free list so that the resulting map reliably has
  the intended number of entries; the entry count is still bounded above by
  `max_length`.
  """
  @spec object(StreamData.t(a), non_neg_integer()) :: StreamData.t(%{optional(String.t()) => a})
        when a: term()
  def object(value_gen, max_length) when is_integer(max_length) and max_length >= 0 do
    key = SD.string(:alphanumeric, min_length: 1, max_length: @max_key_length)

    SD.bind(SD.integer(0..max_length), fn len ->
      SD.bind(SD.uniq_list_of(key, length: len), fn keys ->
        SD.map(SD.list_of(value_gen, length: length(keys)), fn values ->
          keys |> Enum.zip(values) |> Map.new()
        end)
      end)
    end)
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
      array(child, @container_max_length),
      object(child, @container_max_length)
    ])
  end
end
