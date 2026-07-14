# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Reconciler do
  @moduledoc """
  Reconciles two lists of records by a composite key, producing a structured diff.

  ## Example

      left  = [%{id: 1, name: "Alice", age: 30}, %{id: 2, name: "Bob", age: 25}]
      right = [%{id: 1, name: "Alice", age: 31}, %{id: 3, name: "Carol", age: 28}]

      Reconciler.reconcile(left, right, key_fields: [:id])
      #=> %{
      #=>   matched: [
      #=>     %{
      #=>       left: %{id: 1, name: "Alice", age: 30},
      #=>       right: %{id: 1, name: "Alice", age: 31},
      #=>       differences: %{age: %{left: 30, right: 31}}
      #=>     }
      #=>   ],
      #=>   only_in_left:  [%{id: 2, name: "Bob",   age: 25}],
      #=>   only_in_right: [%{id: 3, name: "Carol",  age: 28}]
      #=> }
  """

  @type record_t :: map()
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}

  @type matched_entry :: %{
          left: record_t(),
          right: record_t(),
          differences: diff_map()
        }

  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [record_t()],
          only_in_right: [record_t()]
        }

  @doc """
  Reconciles `left` and `right` lists of maps by the composite key defined in `opts`.

  ## Options

    * `:key_fields` (required) — list of atoms forming the composite match key,
      e.g. `[:id]` or `[:org_id, :user_id]`.

    * `:compare_fields` (optional) — list of atoms to diff on matched pairs.
      Defaults to all fields present in either record, minus the key fields.

  ## Return value

  A map with three keys:

    * `:matched`       — pairs found in both lists, each with a `differences` map.
    * `:only_in_left`  — records found only in `left`.
    * `:only_in_right` — records found only in `right`.
  """
  @spec reconcile([record_t()], [record_t()], keyword()) :: result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_fields_opt = Keyword.get(opts, :compare_fields, nil)

    # Index both sides by composite key — last write wins for duplicate keys,
    # consistent with a pure functional, side-effect-free contract.
    left_index = index_by(left, key_fields)
    right_index = index_by(right, key_fields)

    left_keys = MapSet.new(Map.keys(left_index))
    right_keys = MapSet.new(Map.keys(right_index))

    matched_keys = MapSet.intersection(left_keys, right_keys)
    only_left_keys = MapSet.difference(left_keys, right_keys)
    only_right_keys = MapSet.difference(right_keys, left_keys)

    matched =
      matched_keys
      |> Enum.map(fn key ->
        l = Map.fetch!(left_index, key)
        r = Map.fetch!(right_index, key)
        fields = resolve_compare_fields(l, r, key_fields, compare_fields_opt)
        %{left: l, right: r, differences: diff(l, r, fields)}
      end)

    only_in_left = Enum.map(only_left_keys, &Map.fetch!(left_index, &1))
    only_in_right = Enum.map(only_right_keys, &Map.fetch!(right_index, &1))

    %{matched: matched, only_in_left: only_in_left, only_in_right: only_in_right}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Validates and returns :key_fields from opts, raising on bad input.
  defp fetch_key_fields!(opts) do
    case Keyword.fetch(opts, :key_fields) do
      {:ok, fields} when is_list(fields) and fields != [] ->
        unless Enum.all?(fields, &is_atom/1) do
          raise ArgumentError, ":key_fields must be a non-empty list of atoms"
        end

        fields

      {:ok, _} ->
        raise ArgumentError, ":key_fields must be a non-empty list of atoms"

      :error ->
        raise ArgumentError, "required option :key_fields is missing"
    end
  end

  # Builds a map of composite_key => record for fast O(1) lookups.
  # The composite key is a tuple of the values at the key fields in order,
  # e.g. {org_id_val, user_id_val}.  A single-field key uses a 1-tuple so
  # the representation is uniform and avoids collisions with plain values.
  @spec index_by([record_t()], [atom()]) :: %{tuple() => record_t()}
  defp index_by(records, key_fields) do
    Map.new(records, fn record ->
      {composite_key(record, key_fields), record}
    end)
  end

  @spec composite_key(record_t(), [atom()]) :: tuple()
  defp composite_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  # Determines which fields to compare for a matched pair.
  # If compare_fields is explicitly provided, use it directly.
  # Otherwise, derive it as: (all keys in left ∪ right) minus key_fields.
  @spec resolve_compare_fields(record_t(), record_t(), [atom()], [atom()] | nil) :: [atom()]
  defp resolve_compare_fields(_left, _right, _key_fields, compare_fields)
       when is_list(compare_fields),
       do: compare_fields

  defp resolve_compare_fields(left, right, key_fields, nil) do
    all_fields =
      (Map.keys(left) ++ Map.keys(right))
      |> Enum.uniq()

    key_set = MapSet.new(key_fields)
    Enum.reject(all_fields, &MapSet.member?(key_set, &1))
  end

  # Compares `left` and `right` on the given fields using `==`.
  # Missing fields are treated as nil.
  @spec diff(record_t(), record_t(), [atom()]) :: diff_map()
  defp diff(left, right, fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      lv = Map.get(left, field)
      rv = Map.get(right, field)

      if lv == rv do
        acc
      else
        Map.put(acc, field, %{left: lv, right: rv})
      end
    end)
  end
end
```

## New specification

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
