defmodule JsonGenerators do
  @moduledoc """
  Reusable `StreamData` generators for recursive, JSON-shaped values.

  The generators in this module produce values built exclusively from JSON-compatible
  Elixir terms:

    * `nil` (JSON `null`)
    * booleans
    * integers
    * binaries (alphanumeric strings)
    * lists of JSON values (JSON arrays)
    * maps with binary keys and JSON values (JSON objects)

  ## Depth

  The *depth* of a JSON value is defined as:

    * a scalar (`nil`, boolean, integer, string) has depth `0`;
    * a container (array or object) has depth `1 + max(depth of its children)`, where
      an empty container has depth `1` (the maximum over an empty child set is `0`).

  `value/1` guarantees, **structurally**, that every generated term has a depth less than
  or equal to the requested `max_depth`. The bound is achieved by only ever recursing with
  a strictly smaller budget and by falling back to `scalar/0` once the budget is exhausted;
  no rejection sampling (`StreamData.filter/2`) is involved anywhere, so shrinking stays
  well-behaved and generation never fails with too many consecutive filter misses.

  ## Examples

      use ExUnitProperties

      property "generated values never nest deeper than the bound" do
        check all json <- JsonGenerators.value(3) do
          assert JsonGenerators.depth(json) <= 3
        end
      end

  """

  @typedoc "Any JSON-shaped value produced by this module."
  @type json ::
          nil
          | boolean()
          | integer()
          | String.t()
          | [json()]
          | %{optional(String.t()) => json()}

  @max_scalar_string_length 8
  @default_max_length 5

  @doc """
  Generates a JSON scalar.

  The produced value is one of `nil`, a boolean, an integer, or an alphanumeric string of
  at most #{@max_scalar_string_length} characters. The depth of every generated value is
  always `0`.

  ## Examples

      iex> gen = JsonGenerators.scalar()
      iex> match?(%StreamData{}, gen)
      true

  """
  @spec scalar() :: StreamData.t(json())
  def scalar do
    StreamData.one_of([
      StreamData.constant(nil),
      StreamData.boolean(),
      StreamData.integer(),
      StreamData.string(:alphanumeric, max_length: @max_scalar_string_length)
    ])
  end

  @doc """
  Generates a JSON array: a list of `0..max_length` elements drawn from `element_gen`.

  The length bound is enforced structurally by `StreamData.list_of/2`, so no filtering is
  required. A `max_length` of `0` (or less) yields only the empty list.

  ## Examples

      iex> gen = JsonGenerators.array(JsonGenerators.scalar(), 3)
      iex> match?(%StreamData{}, gen)
      true

  """
  @spec array(StreamData.t(json()), non_neg_integer()) :: StreamData.t([json()])
  def array(element_gen, max_length \\ @default_max_length)

  def array(%StreamData{} = element_gen, max_length) when is_integer(max_length) do
    StreamData.list_of(element_gen, min_length: 0, max_length: max(max_length, 0))
  end

  @doc """
  Generates a JSON object: a map with `0..max_length` entries.

  Each key is a non-empty alphanumeric string and each value is drawn from `value_gen`.

  Because map keys are unique, a generated map may contain *fewer* than the number of
  entries originally drawn (duplicate keys collapse); it never contains more than
  `max_length`. This keeps the bound structural — no filtering is used.

  ## Examples

      iex> gen = JsonGenerators.object(JsonGenerators.scalar(), 3)
      iex> match?(%StreamData{}, gen)
      true

  """
  @spec object(StreamData.t(json()), non_neg_integer()) ::
          StreamData.t(%{optional(String.t()) => json()})
  def object(value_gen, max_length \\ @default_max_length)

  def object(%StreamData{} = value_gen, max_length) when is_integer(max_length) do
    key_gen = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)

    {key_gen, value_gen}
    |> StreamData.tuple()
    |> StreamData.list_of(min_length: 0, max_length: max(max_length, 0))
    |> StreamData.map(&Map.new/1)
  end

  @doc """
  Generates an arbitrary JSON value whose depth is always `<= max_depth`.

  When `max_depth <= 0` the generator always produces a scalar (depth `0`). Otherwise it
  produces a scalar, an array, or an object; the children of a container are drawn from
  `value(max_depth - 1)`, so the recursion terminates and the depth bound holds by
  construction rather than by rejection.

  ## Examples

      iex> gen = JsonGenerators.value(0)
      iex> match?(%StreamData{}, gen)
      true

  """
  @spec value(integer()) :: StreamData.t(json())
  def value(max_depth) when is_integer(max_depth) and max_depth <= 0, do: scalar()

  def value(max_depth) when is_integer(max_depth) do
    child = value(max_depth - 1)

    StreamData.one_of([
      scalar(),
      array(child, @default_max_length),
      object(child, @default_max_length)
    ])
  end

  @doc """
  Computes the depth of a JSON value, as defined in the module documentation.

  Scalars have depth `0`; a container has depth `1 + max(depth of its children)`, and an
  empty container has depth `1`.

  ## Examples

      iex> JsonGenerators.depth(nil)
      0

      iex> JsonGenerators.depth([])
      1

      iex> JsonGenerators.depth(%{"a" => [1, %{}]})
      3

  """
  @spec depth(json()) :: non_neg_integer()
  def depth(value) when is_list(value) do
    1 + Enum.reduce(value, 0, fn element, acc -> max(acc, depth(element)) end)
  end

  def depth(value) when is_map(value) and not is_struct(value) do
    1 + Enum.reduce(value, 0, fn {_key, child}, acc -> max(acc, depth(child)) end)
  end

  def depth(_value), do: 0
end