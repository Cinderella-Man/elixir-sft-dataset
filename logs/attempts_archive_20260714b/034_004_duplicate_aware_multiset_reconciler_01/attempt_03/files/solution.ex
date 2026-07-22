defmodule Reconciler do
  @moduledoc """
  Reconciles two lists of map records by a shared composite key, treating keys
  as a multiset rather than assuming uniqueness.

  The same composite key may appear multiple times on either side. Records are
  grouped by key and the engine reports:

    * which keys are shared by both sides (`:matched`),
    * which keys are exclusive to one side (`:only_in_left`, `:only_in_right`),
    * and which `(key, side)` combinations contain duplicate records
      (`:duplicates`).

  The composite key is defined by the required `:key_fields` option, a list of
  atoms. A key matches exactly when every key field is equal. Within any group,
  records preserve the relative order in which they appeared in their input list.

  The module is pure: it performs no side effects and depends only on the Elixir
  standard library.
  """

  @typedoc "A single record represented as a map."
  @type record :: map()

  @typedoc "A composite key mapping each key field atom to its value."
  @type key_map :: %{optional(atom()) => term()}

  @typedoc "Which input list a group of records came from."
  @type side :: :left | :right

  @typedoc "A matched entry: a key present on both sides with all its records."
  @type matched_entry :: %{key: key_map(), left: [record()], right: [record()]}

  @typedoc "A side-exclusive entry: a key present on only one side."
  @type exclusive_entry :: %{key: key_map(), records: [record()]}

  @typedoc "A duplicate entry: a `(key, side)` pair with more than one record."
  @type duplicate_entry :: %{key: key_map(), side: side(), count: non_neg_integer()}

  @typedoc "The full reconciliation result."
  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [exclusive_entry()],
          only_in_right: [exclusive_entry()],
          duplicates: [duplicate_entry()]
        }

  @doc """
  Reconciles `left` and `right` lists of map records by their composite key.

  `left` and `right` are lists of maps. `opts` is a keyword list that must
  contain `:key_fields`, a non-empty list of atoms forming the composite key.

  Returns a map with four keys: `:matched`, `:only_in_left`, `:only_in_right`
  and `:duplicates`. See the module documentation for the shape of each entry.
  The order of entries within each top-level list is unspecified.

  ## Examples

      iex> left = [%{id: 1, v: :a}, %{id: 1, v: :b}, %{id: 2, v: :c}]
      iex> right = [%{id: 1, v: :x}, %{id: 3, v: :y}]
      iex> res = Reconciler.reconcile(left, right, key_fields: [:id])
      iex> Enum.map(res.matched, & &1.key)
      [%{id: 1}]
      iex> Enum.map(res.only_in_left, & &1.key)
      [%{id: 2}]
      iex> Enum.map(res.only_in_right, & &1.key)
      [%{id: 3}]
      iex> res.duplicates
      [%{key: %{id: 1}, side: :left, count: 2}]
  """
  @spec reconcile([record()], [record()], keyword()) :: result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) do
    key_fields = fetch_key_fields!(opts)

    left_groups = Enum.group_by(left, fn record -> key_tuple(record, key_fields) end)
    right_groups = Enum.group_by(right, fn record -> key_tuple(record, key_fields) end)

    left_keys = MapSet.new(Map.keys(left_groups))
    right_keys = MapSet.new(Map.keys(right_groups))

    %{
      matched: build_matched(left_groups, right_groups, key_fields),
      only_in_left: build_exclusive(left_groups, right_keys, key_fields),
      only_in_right: build_exclusive(right_groups, left_keys, key_fields),
      duplicates:
        build_duplicates(left_groups, :left, key_fields) ++
          build_duplicates(right_groups, :right, key_fields)
    }
  end

  @spec fetch_key_fields!(keyword()) :: [atom(), ...]
  defp fetch_key_fields!(opts) do
    case Keyword.fetch(opts, :key_fields) do
      {:ok, [_ | _] = fields} ->
        if Enum.all?(fields, &is_atom/1) do
          fields
        else
          raise ArgumentError, ":key_fields must be a non-empty list of atoms"
        end

      _other ->
        raise ArgumentError, ":key_fields must be a non-empty list of atoms"
    end
  end

  @spec key_tuple(record(), [atom(), ...]) :: tuple()
  defp key_tuple(record, key_fields) do
    key_fields
    |> Enum.map(fn field -> Map.get(record, field) end)
    |> List.to_tuple()
  end

  @spec build_key_map(tuple(), [atom(), ...]) :: key_map()
  defp build_key_map(key, key_fields) do
    key_fields
    |> Enum.zip(Tuple.to_list(key))
    |> Map.new()
  end

  @spec build_matched(map(), map(), [atom(), ...]) :: [matched_entry()]
  defp build_matched(left_groups, right_groups, key_fields) do
    for {key, left_records} <- left_groups, Map.has_key?(right_groups, key) do
      %{
        key: build_key_map(key, key_fields),
        left: left_records,
        right: Map.fetch!(right_groups, key)
      }
    end
  end

  @spec build_exclusive(map(), MapSet.t(), [atom(), ...]) :: [exclusive_entry()]
  defp build_exclusive(groups, other_keys, key_fields) do
    for {key, records} <- groups, not MapSet.member?(other_keys, key) do
      %{key: build_key_map(key, key_fields), records: records}
    end
  end

  @spec build_duplicates(map(), side(), [atom(), ...]) :: [duplicate_entry()]
  defp build_duplicates(groups, side, key_fields) do
    for {key, records} <- groups, length(records) > 1 do
      %{key: build_key_map(key, key_fields), side: side, count: length(records)}
    end
  end
end
