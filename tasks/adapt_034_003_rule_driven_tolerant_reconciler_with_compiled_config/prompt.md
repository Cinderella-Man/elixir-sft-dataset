# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

# Design Brief: `TolerantReconciler`

## Problem

Two lists of records must be reconciled against each other, but strict equality is too blunt: a 0.005 rounding difference on a money column, or a stray capital letter in a name, should not count as a mismatch. The needed component is an Elixir module called `TolerantReconciler` that reconciles two lists of records using **per-field comparison rules** instead of strict equality. The design is split into a validated-configuration stage and an execution stage.

## Constraints

- Pure functions — no processes, no side effects, no external dependencies. Elixir standard library only.
- Deliver the complete module in a single file.

## Required Interface

1. **`TolerantReconciler.compile(opts)`** — validates a keyword list and returns `{:ok, config}` or `{:error, reason}`.

   Options:
   - `:key_fields` (required) — a non-empty list of atoms forming the composite key.
   - `:compare_fields` (optional) — a list of atoms to compare on matched pairs. If omitted or `nil`, compare every field present in either record of the pair, minus the key fields.
   - `:rules` (optional) — a keyword list of `field => rule`. Any compared field with no entry here uses the `:exact` rule. Defaults to `[]`.

   Rules:
   - `:exact` — the values differ unless `left == right`.
   - `{:numeric, tolerance}` — `tolerance` must be a number `>= 0`. If **both** values are numbers, they are considered equal when `abs(left - right) <= tolerance`. If either value is not a number, fall back to `==`.
   - `:case_insensitive` — if **both** values are binaries, they are considered equal when their trimmed, downcased forms are equal (`String.trim/1` then `String.downcase/1`). If either value is not a binary, fall back to `==`.
   - `:ignore` — the field is never compared and can never appear in a differences map, even if it is listed in `:compare_fields`.

   Errors — return exactly these error tuples (first failure wins is not required — any one of the applicable errors is acceptable when several apply):
   - `{:error, :missing_key_fields}` — `:key_fields` is absent.
   - `{:error, :invalid_key_fields}` — `:key_fields` is present but is not a non-empty list of atoms.
   - `{:error, :invalid_compare_fields}` — `:compare_fields` is present, not `nil`, and is not a list of atoms.
   - `{:error, :invalid_rules}` — `:rules` is not a keyword list (a list of `{atom, term}` pairs).
   - `{:error, {:invalid_rule, field}}` — the rule given for `field` is not one of the four rules above (including a `{:numeric, tolerance}` whose tolerance is not a number `>= 0`).

   On success the return is `{:ok, config}`. The shape of `config` is up to you — treat it as opaque; it is only ever passed back into `run/3`.

2. **`TolerantReconciler.run(config, left, right)`** — runs the reconciliation, where `left` and `right` are lists of maps. Returns a report map.

   Matching: records are matched across the two lists by **exact** equality on all key fields (comparison rules apply to compared fields only, never to key fields). A key field missing from a record is treated as `nil`. If a key repeats within one list, the last record with that key wins.

   The report is a map with three keys:
   - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` for keys present on both sides. `diff_map` is `%{field => %{left: left_value, right: right_value, rule: rule}}` for every compared field whose values differ **under its rule**, where `rule` is the rule that was applied (`:exact` when the field had no entry in `:rules`). `diff_map` is `%{}` when the pair agrees under all rules. A compared field missing from a record is treated as `nil`. The `:left` and `:right` records are the full originals.
   - `:only_in_left` — records whose key appears only in `left`.
   - `:only_in_right` — records whose key appears only in `right`.

   Order of results does not matter.

3. **`TolerantReconciler.field_summary(report)`** — takes a report from `run/3` and returns a map of `%{field => number_of_matched_pairs_where_it_differed}`. Given a report from `run/3`, return a map from field name to the number of entries in `:matched` whose `differences` map contains that field. Fields that never differed are **omitted** from the map (so an all-clean report gives `%{}`).

## Acceptance Criteria

- `compile/1` validates the keyword list, returns `{:ok, config}` on success and the exact error tuples above on failure, applies the rule semantics described (`:exact`, `{:numeric, tolerance}` with `tolerance` a number `>= 0`, `:case_insensitive`, `:ignore`), and defaults `:rules` to `[]` with `:exact` for any compared field lacking an entry.
- `run/3` matches by exact equality on all key fields (missing key field treated as `nil`, last record wins on repeated keys within a list), produces `:matched`, `:only_in_left`, and `:only_in_right`, and builds each `diff_map` correctly (missing compared field treated as `nil`, `:ignore` fields never present, `%{}` when a pair agrees).
- `field_summary/1` returns a map from field to the count of `:matched` entries whose `differences` contains that field, omitting fields that never differed (`%{}` for an all-clean report).
- The module is pure — no processes, no side effects, no external dependencies, Elixir standard library only — and delivered complete in a single file.
