defmodule Reconciler do
  @moduledoc """
  Reconciles two lists of record maps by a shared composite key, producing a
  structured diff.

  Unlike a plain exact-match diff, `Reconciler` supports **pluggable per-field
  comparators** so that individual fields can be compared with numeric
  tolerance, case-insensitivity, or arbitrary custom logic instead of always
  using `==`.

  Records are matched across the two lists by an exact match on the configured
  key fields. Comparators only affect how non-key fields are diffed; they never
  influence key matching.

  The result is a map with three keys:

    * `:matched` — entries whose key exists in both lists, each carrying the full
      left and right record plus a map of differing fields.
    * `:only_in_left` — records whose key exists only in the left list.
    * `:only_in_right` — records whose key exists only in the right list.
  """

  @typedoc "A single record: an arbitrary map of field => value."
  @type record :: map()

  @typedoc "A comparator applied to a single compared field."
  @type comparator :: {:numeric, number()} | :case_insensitive | (term(), term() -> term())

  @typedoc "The per-field difference map for a matched pair."
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}

  @typedoc "A single matched entry."
  @type matched_entry :: %{left: record(), right: record(), differences: diff_map()}

  @typedoc "The full reconciliation result."
  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  @doc """
  Reconciles `left` and `right` (both lists of maps) by a shared key.

  ## Options

    * `:key_fields` (required) — list of atoms forming the composite key. Matching
      is always exact across all key fields.
    * `:compare_fields` (optional) — list of atoms to diff on matched records. When
      omitted or `nil`, all fields except the key fields (across both records) are
      compared.
    * `:comparators` (optional) — map of `%{field => comparator}`. Fields absent
      from this map are compared with `==`. Defaults to `%{}`.

  Returns a map with `:matched`, `:only_in_left`, and `:only_in_right`.

  ## Examples

      iex> left = [%{id: 1, name: "Ann"}, %{id: 2, name: "Bo"}]
      iex> right = [%{id: 1, name: "ann"}, %{id: 3, name: "Cy"}]
      iex> result =
      ...>   Reconciler.reconcile(left, right,
      ...>     key_fields: [:id],
      ...>     comparators: %{name: :case_insensitive}
      ...>   )
      iex> Enum.map(result.matched, & &1.differences)
      [%{}]
      iex> result.only_in_left
      [%{id: 2, name: "Bo"}]
      iex> result.only_in_right
      [%{id: 3, name: "Cy"}]
  """
  @spec reconcile([record()], [record()], keyword()) :: result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = Keyword.fetch!(opts, :key_fields)
    compare_fields = Keyword.get(opts, :compare_fields)
    comparators = Keyword.get(opts, :comparators) || %{}

    left_index = index_by_key(left, key_fields)
    right_index = index_by_key(right, key_fields)

    left_keys = MapSet.new(Map.keys(left_index))
    right_keys = MapSet.new(Map.keys(right_index))

    matched_keys = MapSet.intersection(left_keys, right_keys)

    matched =
      Enum.map(MapSet.to_list(matched_keys), fn key ->
        left_record = Map.fetch!(left_index, key)
        right_record = Map.fetch!(right_index, key)
        fields = fields_to_compare(left_record, right_record, key_fields, compare_fields)
        differences = diff_records(left_record, right_record, fields, comparators)
        %{left: left_record, right: right_record, differences: differences}
      end)

    only_in_left =
      left_keys
      |> MapSet.difference(right_keys)
      |> MapSet.to_list()
      |> Enum.map(&Map.fetch!(left_index, &1))

    only_in_right =
      right_keys
      |> MapSet.difference(left_keys)
      |> MapSet.to_list()
      |> Enum.map(&Map.fetch!(right_index, &1))

    %{matched: matched, only_in_left: only_in_left, only_in_right: only_in_right}
  end

  @spec index_by_key([record()], [atom()]) :: %{optional(list()) => record()}
  defp index_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      Map.put(acc, key_of(record, key_fields), record)
    end)
  end

  @spec key_of(record(), [atom()]) :: list()
  defp key_of(record, key_fields) do
    Enum.map(key_fields, fn field -> Map.get(record, field) end)
  end

  @spec fields_to_compare(record(), record(), [atom()], [atom()] | nil) :: [atom()]
  defp fields_to_compare(_left, _right, _key_fields, compare_fields)
       when is_list(compare_fields) do
    compare_fields
  end

  defp fields_to_compare(left, right, key_fields, _compare_fields) do
    key_set = MapSet.new(key_fields)

    left
    |> Map.keys()
    |> Enum.concat(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_set, &1))
  end

  @spec diff_records(record(), record(), [atom()], map()) :: diff_map()
  defp diff_records(left, right, fields, comparators) do
    Enum.reduce(fields, %{}, fn field, acc ->
      left_val = Map.get(left, field)
      right_val = Map.get(right, field)
      comparator = Map.get(comparators, field)

      if fields_equal?(left_val, right_val, comparator) do
        acc
      else
        Map.put(acc, field, %{left: left_val, right: right_val})
      end
    end)
  end

  @spec fields_equal?(term(), term(), comparator() | nil) :: boolean()
  defp fields_equal?(left_val, right_val, {:numeric, tolerance})
       when is_number(left_val) and is_number(right_val) and is_number(tolerance) do
    abs(left_val - right_val) <= tolerance
  end

  defp fields_equal?(left_val, right_val, :case_insensitive)
       when is_binary(left_val) and is_binary(right_val) do
    String.downcase(left_val) == String.downcase(right_val)
  end

  defp fields_equal?(left_val, right_val, fun) when is_function(fun, 2) do
    if fun.(left_val, right_val), do: true, else: false
  end

  defp fields_equal?(left_val, right_val, _comparator) do
    left_val == right_val
  end
end
