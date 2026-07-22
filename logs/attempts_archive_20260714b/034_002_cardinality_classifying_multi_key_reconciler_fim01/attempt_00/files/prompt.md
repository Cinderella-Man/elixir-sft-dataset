Implement the public `classify/3` function.

It takes `left` and `right` (lists of record maps) and `opts` (a keyword list), and
returns the six-key report map described below. All of the helper functions it needs
already exist in the module — your job is only to wire them together.

What it must do:

1. Read `:key_fields` from `opts` and pass it through `validate_key_fields/1`, and read
   `:compare_fields` from `opts` and pass it through `validate_compare_fields/1`. These
   raise `ArgumentError` on malformed input, so a missing or non-atom-list `:key_fields`
   must reach the validator rather than being defaulted away. An absent `:compare_fields`
   is `nil`, which means "compare every field present in either record of a pair, minus
   the key fields".
2. Group each side by composite key with `group_by_key/2`. Note that `group_by_key/2`
   accumulates each group by prepending, so a group's records come out in **reverse**
   input order — whenever you hand a group to an entry or to `classify_pair/5`, reverse
   it first so that records inside a group are in their original input order.
3. Build the empty report: a map with one entry per key in `@report_keys`, each starting
   as `[]`.
4. Compute the union of the keys of both group maps (e.g. with `MapSet`), and reduce over
   it, accumulating into the report:
   * key only on the right → prepend a `%{key: key_map, records: [records]}` entry to
     `:only_in_right` via `prepend/3`;
   * key only on the left → prepend the same shape to `:only_in_left`;
   * key on both sides → delegate to `classify_pair/5`, passing the accumulator, the key
     map, the (reversed) left group, the (reversed) right group, and a config map with
     `:key_fields` and `:compare_fields`. `classify_pair/5` handles the one-to-one /
     one-to-many / many-to-one / many-to-many split and the difference diffing.
5. Every entry carries `:key`, a `%{key_field => value}` map built from the composite key
   tuple with `key_map/2`.
6. The function should accept only list arguments for `left`, `right` and `opts` (guard
   accordingly). The order of entries within each report list is unspecified.

```elixir
defmodule MultiKeyReconciler do
  @moduledoc """
  Reconciles two lists of record maps whose composite keys may repeat.

  Instead of assuming a clean one-to-one join, every key present on both sides is
  classified by the *cardinality* of its two groups:

    * `:one_to_one` — exactly one record on each side (the only case where a field
      level diff is computed);
    * `:one_to_many`, `:many_to_one`, `:many_to_many` — ambiguous pairings, handed
      back as raw groups because resolving them would require a tie-break rule;
    * `:only_in_left` / `:only_in_right` — keys seen on a single side.

  Grouping is exact: two records share a key when their values at every key field
  are `==`. A key field absent from a record contributes `nil`. Records inside a
  group preserve their original input order.

  ## Example

      iex> left = [%{id: 1, name: "a"}, %{id: 2, name: "b"}]
      iex> right = [%{id: 1, name: "A"}, %{id: 3, name: "c"}]
      iex> report = MultiKeyReconciler.classify(left, right, key_fields: [:id])
      iex> MultiKeyReconciler.counts(report)[:one_to_one]
      1

  """

  @type entry_record :: map()
  @type key_map :: %{optional(atom()) => term()}
  @type differences :: %{optional(atom()) => %{left: term(), right: term()}}
  @type report :: %{
          one_to_one: [map()],
          one_to_many: [map()],
          many_to_one: [map()],
          many_to_many: [map()],
          only_in_left: [map()],
          only_in_right: [map()]
        }

  @report_keys [
    :one_to_one,
    :one_to_many,
    :many_to_one,
    :many_to_many,
    :only_in_left,
    :only_in_right
  ]

  @doc """
  Classifies every composite key found in `left` and `right`.

  ## Options

    * `:key_fields` (required) — non-empty list of atoms forming the composite key.
      Raises `ArgumentError` when missing or malformed.
    * `:compare_fields` (optional) — list of atoms to diff on a one-to-one pair.
      Defaults to every field present in either record of the pair, minus the key
      fields.

  Returns a report map with the keys `#{inspect(@report_keys)}`.
  """
  def classify(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    # TODO
  end

  @doc """
  Counts the entries of a report produced by `classify/3`.

  Returns a map with one count per report list, plus `:ambiguous`, the sum of the
  `:one_to_many`, `:many_to_one` and `:many_to_many` counts.
  """
  @spec counts(report()) :: %{optional(atom()) => non_neg_integer()}
  def counts(report) when is_map(report) do
    counts = Map.new(@report_keys, fn key -> {key, length(Map.fetch!(report, key))} end)

    ambiguous = counts.one_to_many + counts.many_to_one + counts.many_to_many

    Map.put(counts, :ambiguous, ambiguous)
  end

  # --- internals -------------------------------------------------------------

  defp classify_pair(acc, key_map, [l], [r], config) do
    differences = differences(l, r, config)
    prepend(acc, :one_to_one, %{key: key_map, left: l, right: r, differences: differences})
  end

  defp classify_pair(acc, key_map, [l], rights, _config) do
    prepend(acc, :one_to_many, %{key: key_map, left: l, right: rights})
  end

  defp classify_pair(acc, key_map, lefts, [r], _config) do
    prepend(acc, :many_to_one, %{key: key_map, left: lefts, right: r})
  end

  defp classify_pair(acc, key_map, lefts, rights, _config) do
    prepend(acc, :many_to_many, %{key: key_map, left: lefts, right: rights})
  end

  defp prepend(acc, bucket, entry), do: Map.update!(acc, bucket, &[entry | &1])

  defp differences(left, right, %{key_fields: key_fields, compare_fields: compare_fields}) do
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
    |> Enum.concat(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in key_fields))
  end

  defp fields_to_compare(_left, _right, _key_fields, compare_fields), do: compare_fields

  defp group_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      key = composite_key(record, key_fields)
      Map.update(acc, key, [record], &[record | &1])
    end)
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

  defp validate_key_fields(key_fields)
       when is_list(key_fields) and key_fields != [] do
    if Enum.all?(key_fields, &is_atom/1) do
      key_fields
    else
      raise ArgumentError,
            ":key_fields must be a non-empty list of atoms, got: #{inspect(key_fields)}"
    end
  end

  defp validate_key_fields(other) do
    raise ArgumentError,
          ":key_fields must be a non-empty list of atoms, got: #{inspect(other)}"
  end

  defp validate_compare_fields(nil), do: nil

  defp validate_compare_fields(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError,
            ":compare_fields must be a list of atoms, got: #{inspect(fields)}"
    end
  end

  defp validate_compare_fields(other) do
    raise ArgumentError, ":compare_fields must be a list of atoms, got: #{inspect(other)}"
  end
end
```