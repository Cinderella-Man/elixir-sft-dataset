defmodule BagReconciler do
  @moduledoc """
  Reconciles two lists of records (maps) whose keys may repeat.

  Unlike a set-based reconciler, each side is treated as a *bag* (multiset): the same key
  may occur several times in `left` and/or `right`. Occurrences sharing a key are paired up
  positionally — the 1st left occurrence with the 1st right occurrence, the 2nd with the
  2nd, and so on — and any leftovers are reported as unmatched.

  Records are plain maps. A *key_map* is a map `%{field => value}` built from the configured
  key fields (a missing field contributes `nil`). A *diff_map* is
  `%{field => %{left: left_value, right: right_value}}` and contains an entry only for the
  fields whose values differ.

  The module is pure: no processes, no side effects, Elixir standard library only.
  """

  @type record :: map()
  @type key_map :: map()
  @type diff_map :: %{optional(atom()) => %{left: any(), right: any()}}

  @type pair :: %{
          key: key_map(),
          index: non_neg_integer(),
          left: record(),
          right: record(),
          differences: diff_map()
        }

  @type unmatched :: %{key: key_map(), record: record()}

  @type duplicate :: %{
          key: key_map(),
          left_count: non_neg_integer(),
          right_count: non_neg_integer()
        }

  @type result :: %{
          pairs: [pair()],
          unmatched_left: [unmatched()],
          unmatched_right: [unmatched()],
          duplicate_keys: [duplicate()]
        }

  @doc """
  Reconciles the `left` and `right` bags of records.

  ## Options

    * `:key_fields` (required) — a non-empty list of atoms forming the composite key.
      Anything else raises `ArgumentError`.
    * `:compare_fields` (optional) — a list of atoms to diff on paired records. When omitted
      or `nil`, every field present in either record of the pair is compared, except the key
      fields.

  Returns a map with the keys `:pairs`, `:unmatched_left`, `:unmatched_right` and
  `:duplicate_keys`. The order of entries within each list is unspecified.

  ## Examples

      iex> left = [%{id: 1, v: :a}, %{id: 1, v: :b}]
      iex> right = [%{id: 1, v: :a}]
      iex> result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])
      iex> Enum.map(result.pairs, & &1.index)
      [0]
      iex> result.unmatched_left
      [%{key: %{id: 1}, record: %{id: 1, v: :b}}]
      iex> result.duplicate_keys
      [%{key: %{id: 1}, left_count: 2, right_count: 1}]

  """
  @spec reconcile_bags([record()], [record()], keyword()) :: result()
  def reconcile_bags(left, right, opts)
      when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = validate_key_fields(Keyword.get(opts, :key_fields))
    compare_fields = validate_compare_fields(Keyword.get(opts, :compare_fields))

    left_groups = group_by_key(left, key_fields)
    right_groups = group_by_key(right, key_fields)

    keys = Enum.uniq(Map.keys(left_groups) ++ Map.keys(right_groups))

    initial = %{pairs: [], unmatched_left: [], unmatched_right: [], duplicate_keys: []}

    Enum.reduce(keys, initial, fn key, acc ->
      lefts = Map.get(left_groups, key, [])
      rights = Map.get(right_groups, key, [])
      left_count = length(lefts)
      right_count = length(rights)

      %{
        pairs: build_pairs(key, lefts, rights, key_fields, compare_fields) ++ acc.pairs,
        unmatched_left: leftovers(key, lefts, right_count) ++ acc.unmatched_left,
        unmatched_right: leftovers(key, rights, left_count) ++ acc.unmatched_right,
        duplicate_keys: duplicate_entry(key, left_count, right_count) ++ acc.duplicate_keys
      }
    end)
  end

  @doc """
  Counts how many records in `records` carry each key built from `key_fields`.

  Returns a map of `key_map => count`. Fields missing from a record contribute `nil`.

  ## Examples

      iex> BagReconciler.key_counts([%{id: 1}, %{id: 1}, %{id: 2}], [:id])
      %{%{id: 1} => 2, %{id: 2} => 1}

  """
  @spec key_counts([record()], [atom()]) :: %{optional(key_map()) => pos_integer()}
  def key_counts(records, key_fields) when is_list(records) do
    fields = validate_key_fields(key_fields)

    Enum.reduce(records, %{}, fn record, acc ->
      Map.update(acc, key_of(record, fields), 1, fn count -> count + 1 end)
    end)
  end

  # -- internals -------------------------------------------------------------

  defp validate_key_fields(fields) when is_list(fields) and fields != [] do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise_key_fields(fields)
    end
  end

  defp validate_key_fields(fields), do: raise_key_fields(fields)

  defp raise_key_fields(fields) do
    raise ArgumentError,
          ":key_fields must be a non-empty list of atoms, got: #{inspect(fields)}"
  end

  defp validate_compare_fields(nil), do: nil

  defp validate_compare_fields(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise_compare_fields(fields)
    end
  end

  defp validate_compare_fields(fields), do: raise_compare_fields(fields)

  defp raise_compare_fields(fields) do
    raise ArgumentError,
          ":compare_fields must be a list of atoms or nil, got: #{inspect(fields)}"
  end

  defp key_of(record, key_fields) do
    Map.new(key_fields, fn field -> {field, Map.get(record, field)} end)
  end

  defp group_by_key(records, key_fields) do
    records
    |> Enum.reduce(%{}, fn record, acc ->
      Map.update(acc, key_of(record, key_fields), [record], fn kept -> [record | kept] end)
    end)
    |> Map.new(fn {key, reversed} -> {key, Enum.reverse(reversed)} end)
  end

  defp build_pairs(key, lefts, rights, key_fields, compare_fields) do
    lefts
    |> Enum.zip(rights)
    |> Enum.with_index()
    |> Enum.map(fn {{left, right}, index} ->
      %{
        key: key,
        index: index,
        left: left,
        right: right,
        differences: diff(left, right, key_fields, compare_fields)
      }
    end)
  end

  defp leftovers(key, records, paired_count) do
    records
    |> Enum.drop(paired_count)
    |> Enum.map(fn record -> %{key: key, record: record} end)
  end

  defp duplicate_entry(key, left_count, right_count)
       when left_count > 1 or right_count > 1 do
    [%{key: key, left_count: left_count, right_count: right_count}]
  end

  defp duplicate_entry(_key, _left_count, _right_count), do: []

  defp diff(left, right, key_fields, compare_fields) do
    left
    |> fields_to_compare(right, key_fields, compare_fields)
    |> Enum.reduce(%{}, fn field, acc ->
      left_value = Map.get(left, field)
      right_value = Map.get(right, field)

      if left_value == right_value do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value})
      end
    end)
  end

  defp fields_to_compare(left, right, key_fields, nil) do
    (Map.keys(left) ++ Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(fn field -> field in key_fields end)
  end

  defp fields_to_compare(_left, _right, _key_fields, compare_fields), do: compare_fields
end
