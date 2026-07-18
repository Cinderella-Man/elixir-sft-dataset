# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `counts` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `MultiKeyReconciler` that reconciles two lists of records whose keys may repeat, classifying every shared key by its match *cardinality* instead of assuming a one-to-one join.

## Public API

- `MultiKeyReconciler.classify(left, right, opts)` — `left` and `right` are lists of maps, `opts` is a keyword list. Returns a report map (described below).
- `MultiKeyReconciler.counts(report)` — takes a report produced by `classify/3` and returns a map of entry counts (described below).

## Options

- `:key_fields` (required) — a non-empty list of atoms forming the composite key (e.g. `[:id]` or `[:org_id, :user_id]`). If it is missing, or is not a non-empty list of atoms, raise `ArgumentError`.
- `:compare_fields` (optional) — a list of atoms to diff on a one-to-one pair. If omitted or `nil`, compare every field present in either record of the pair, minus the key fields.

## Grouping

Group each side by its composite key. A record's composite key is the tuple of its values at the key fields, in the order given; a key field missing from a record contributes `nil`. Records that share a composite key form one group, and **the records inside a group keep their original input order**.

Every key present on **both** sides is classified by the sizes of its two groups. Every entry carries a `:key` field, which is a **map** of `%{key_field => value}` for that group.

## The report

`classify/3` returns a map with exactly these six keys:

- `:one_to_one` — one left record and one right record for the key. Entries are
  `%{key: key_map, left: record, right: record, differences: diff_map}`.
  `diff_map` is `%{field => %{left: left_value, right: right_value}}` for each compared field whose values differ under `==`; it is `%{}` when the pair agrees on all compared fields. A compared field missing from a record is treated as `nil`. The `:left` and `:right` records are the full originals, even if some of their fields were excluded from comparison.
- `:one_to_many` — one left record, two or more right records. Entries are
  `%{key: key_map, left: record, right: [records]}`.
- `:many_to_one` — two or more left records, exactly one right record. Entries are
  `%{key: key_map, left: [records], right: record}`.
- `:many_to_many` — two or more records on both sides. Entries are
  `%{key: key_map, left: [records], right: [records]}`.
- `:only_in_left` — keys present only in `left`. Entries are `%{key: key_map, records: [records]}` (the group, which may hold one or many records).
- `:only_in_right` — keys present only in `right`. Entries are `%{key: key_map, records: [records]}`.

No `differences` map is computed for ambiguous (`one_to_many`, `many_to_one`, `many_to_many`) groups — those pairings are considered unresolvable without a tie-break rule, so the raw groups are handed back as-is.

The order of entries within each of the six lists is unspecified; only the order of records inside a group is guaranteed.

## counts/1

`MultiKeyReconciler.counts(report)` returns a map with these keys, where each value is the **number of entries** (i.e. the number of keys) in the corresponding report list:

`:one_to_one`, `:one_to_many`, `:many_to_one`, `:many_to_many`, `:only_in_left`, `:only_in_right`, plus

- `:ambiguous` — the sum of `:one_to_many`, `:many_to_one`, and `:many_to_many`.

## Constraints

- Pure functions — no processes, no side effects, no external dependencies. Elixir standard library only.
- Key matching is exact: values must be `==` on every key field.

Give me the complete module in a single file.

## The module with `counts` missing

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
  @spec classify([entry_record()], [entry_record()], keyword()) :: report()
  def classify(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = validate_key_fields(Keyword.get(opts, :key_fields))
    compare_fields = validate_compare_fields(Keyword.get(opts, :compare_fields))

    left_groups = group_by_key(left, key_fields)
    right_groups = group_by_key(right, key_fields)

    empty = Map.new(@report_keys, fn key -> {key, []} end)

    left_keys = left_groups |> Map.keys() |> MapSet.new()
    right_keys = right_groups |> Map.keys() |> MapSet.new()
    all_keys = MapSet.union(left_keys, right_keys)

    Enum.reduce(all_keys, empty, fn key, acc ->
      key_map = key_map(key, key_fields)

      case {Map.get(left_groups, key), Map.get(right_groups, key)} do
        {nil, rights} ->
          prepend(acc, :only_in_right, %{key: key_map, records: Enum.reverse(rights)})

        {lefts, nil} ->
          prepend(acc, :only_in_left, %{key: key_map, records: Enum.reverse(lefts)})

        {lefts, rights} ->
          classify_pair(acc, key_map, Enum.reverse(lefts), Enum.reverse(rights), %{
            key_fields: key_fields,
            compare_fields: compare_fields
          })
      end
    end)
  end

  def counts(report) when is_map(report) do
    # TODO
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

Give me only the complete implementation of `counts` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
