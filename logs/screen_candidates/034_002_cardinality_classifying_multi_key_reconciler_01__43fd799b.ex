defmodule MultiKeyReconciler do
  @moduledoc """
  Reconciles two lists of record maps whose composite keys may repeat.

  Unlike a naive join, `classify/3` never assumes a key identifies at most one record per
  side. Instead it groups each side by the composite key and classifies every shared key by
  the *cardinality* of the two groups:

    * `1 x 1` — resolvable, so a field-level difference map is computed;
    * `1 x N`, `N x 1`, `N x M` — ambiguous, so the raw groups are handed back untouched.

  Keys that appear on only one side are reported separately.

  ## Example

      iex> left = [%{id: 1, name: "a"}, %{id: 2, name: "b"}, %{id: 2, name: "c"}]
      iex> right = [%{id: 1, name: "z"}, %{id: 2, name: "b"}]
      iex> report = MultiKeyReconciler.classify(left, right, key_fields: [:id])
      iex> MultiKeyReconciler.counts(report).many_to_one
      1

  All functions are pure; no processes, no side effects, standard library only.
  """

  @type record :: map()
  @type key_map :: %{optional(atom()) => term()}
  @type differences :: %{optional(atom()) => %{left: term(), right: term()}}

  @type report :: %{
          one_to_one: [%{key: key_map(), left: record(), right: record(), differences:
                         differences()}],
          one_to_many: [%{key: key_map(), left: record(), right: [record()]}],
          many_to_one: [%{key: key_map(), left: [record()], right: record()}],
          many_to_many: [%{key: key_map(), left: [record()], right: [record()]}],
          only_in_left: [%{key: key_map(), records: [record()]}],
          only_in_right: [%{key: key_map(), records: [record()]}]
        }

  @type count_report :: %{
          one_to_one: non_neg_integer(),
          one_to_many: non_neg_integer(),
          many_to_one: non_neg_integer(),
          many_to_many: non_neg_integer(),
          only_in_left: non_neg_integer(),
          only_in_right: non_neg_integer(),
          ambiguous: non_neg_integer()
        }

  @doc """
  Classifies every composite key across `left` and `right` by match cardinality.

  ## Options

    * `:key_fields` (required) — non-empty list of atoms forming the composite key. Raises
      `ArgumentError` when missing or not a non-empty list of atoms.
    * `:compare_fields` (optional) — list of atoms to diff on a one-to-one pair. When omitted
      or `nil`, every field present in either record of the pair is compared, minus the key
      fields.

  Returns a map with the keys `:one_to_one`, `:one_to_many`, `:many_to_one`, `:many_to_many`,
  `:only_in_left` and `:only_in_right`. Entry order within each list is unspecified; record
  order inside a group follows the input order.
  """
  @spec classify([record()], [record()], keyword()) :: report()
  def classify(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = validate_key_fields(Keyword.get(opts, :key_fields))
    compare_fields = validate_compare_fields(Keyword.get(opts, :compare_fields))

    left_groups = group_by_key(left, key_fields)
    right_groups = group_by_key(right, key_fields)

    left_keys = MapSet.new(Map.keys(left_groups))
    right_keys = MapSet.new(Map.keys(right_groups))

    shared = MapSet.intersection(left_keys, right_keys)

    empty = %{
      one_to_one: [],
      one_to_many: [],
      many_to_one: [],
      many_to_many: [],
      only_in_left: [],
      only_in_right: []
    }

    report =
      Enum.reduce(shared, empty, fn key, acc ->
        classify_key(
          key,
          Map.fetch!(left_groups, key),
          Map.fetch!(right_groups, key),
          key_fields,
          compare_fields,
          acc
        )
      end)

    report
    |> Map.put(:only_in_left, only_entries(left_groups, left_keys, right_keys, key_fields))
    |> Map.put(:only_in_right, only_entries(right_groups, right_keys, left_keys, key_fields))
  end

  @doc """
  Summarises a report produced by `classify/3` as entry counts per category.

  The returned map holds the six report categories plus `:ambiguous`, the sum of
  `:one_to_many`, `:many_to_one` and `:many_to_many`.
  """
  @spec counts(report()) :: count_report()
  def counts(report) when is_map(report) do
    one_to_many = length(Map.fetch!(report, :one_to_many))
    many_to_one = length(Map.fetch!(report, :many_to_one))
    many_to_many = length(Map.fetch!(report, :many_to_many))

    %{
      one_to_one: length(Map.fetch!(report, :one_to_one)),
      one_to_many: one_to_many,
      many_to_one: many_to_one,
      many_to_many: many_to_many,
      only_in_left: length(Map.fetch!(report, :only_in_left)),
      only_in_right: length(Map.fetch!(report, :only_in_right)),
      ambiguous: one_to_many + many_to_one + many_to_many
    }
  end

  # -- Option validation ------------------------------------------------------------------

  defp validate_key_fields(fields) when is_list(fields) and fields != [] do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError,
            ":key_fields must be a non-empty list of atoms, got: #{inspect(fields)}"
    end
  end

  defp validate_key_fields(other) do
    raise ArgumentError, ":key_fields must be a non-empty list of atoms, got: #{inspect(other)}"
  end

  defp validate_compare_fields(nil), do: nil

  defp validate_compare_fields(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError, ":compare_fields must be a list of atoms, got: #{inspect(fields)}"
    end
  end

  defp validate_compare_fields(other) do
    raise ArgumentError, ":compare_fields must be a list of atoms, got: #{inspect(other)}"
  end

  # -- Grouping ---------------------------------------------------------------------------

  defp group_by_key(records, key_fields) do
    records
    |> Enum.reduce(%{}, fn record, acc ->
      key = composite_key(record, key_fields)
      Map.update(acc, key, [record], &[record | &1])
    end)
    |> Map.new(fn {key, reversed} -> {key, Enum.reverse(reversed)} end)
  end

  defp composite_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  defp key_map(key_tuple, key_fields) do
    key_fields
    |> Enum.zip(Tuple.to_list(key_tuple))
    |> Map.new()
  end

  # -- Classification ---------------------------------------------------------------------

  defp classify_key(key, [l], [r], key_fields, compare_fields, acc) do
    entry = %{
      key: key_map(key, key_fields),
      left: l,
      right: r,
      differences: differences(l, r, key_fields, compare_fields)
    }

    Map.update!(acc, :one_to_one, &[entry | &1])
  end

  defp classify_key(key, [l], rights, key_fields, _compare_fields, acc) do
    entry = %{key: key_map(key, key_fields), left: l, right: rights}
    Map.update!(acc, :one_to_many, &[entry | &1])
  end

  defp classify_key(key, lefts, [r], key_fields, _compare_fields, acc) do
    entry = %{key: key_map(key, key_fields), left: lefts, right: r}
    Map.update!(acc, :many_to_one, &[entry | &1])
  end

  defp classify_key(key, lefts, rights, key_fields, _compare_fields, acc) do
    entry = %{key: key_map(key, key_fields), left: lefts, right: rights}
    Map.update!(acc, :many_to_many, &[entry | &1])
  end

  defp only_entries(groups, own_keys, other_keys, key_fields) do
    own_keys
    |> MapSet.difference(other_keys)
    |> Enum.map(fn key ->
      %{key: key_map(key, key_fields), records: Map.fetch!(groups, key)}
    end)
  end

  # -- Differences ------------------------------------------------------------------------

  defp differences(left, right, key_fields, compare_fields) do
    fields = fields_to_compare(left, right, key_fields, compare_fields)

    Enum.reduce(fields, %{}, fn field, acc ->
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
    left
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(right)))
    |> MapSet.difference(MapSet.new(key_fields))
    |> Enum.filter(&is_atom/1)
  end

  defp fields_to_compare(_left, _right, _key_fields, compare_fields), do: compare_fields
end