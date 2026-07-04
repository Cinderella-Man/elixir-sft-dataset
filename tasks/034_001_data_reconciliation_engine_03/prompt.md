# Task: Implement `resolve_compare_fields/4`

You are working inside the `Reconciler` module, which reconciles two lists of
records (maps) by a composite key and produces a structured diff. The whole
module is given below, but the body of the private helper
`resolve_compare_fields/4` has been removed and replaced with `# TODO`. Your job
is to implement that one function.

## What `resolve_compare_fields/4` must do

`resolve_compare_fields(left, right, key_fields, compare_fields)` determines the
list of field atoms that should be diffed for a single matched pair of records.

- `left` and `right` are the two matched records (maps).
- `key_fields` is the list of atoms forming the composite match key.
- `compare_fields` is either an explicit list of atoms, or `nil`.

Behaviour:

1. **Explicit list case** — when `compare_fields` is a list, return it verbatim.
   The caller has said exactly which fields to diff, so honor it directly
   without adding or removing anything.

2. **`nil` case** — when `compare_fields` is `nil`, derive the fields to compare:
   - Take the union of all keys present in either `left` or `right`
     (`Map.keys(left) ++ Map.keys(right)`), de-duplicated.
   - Remove the `key_fields` from that set, since the key fields are what the
     records were matched on and should not appear in the diff.
   - Return the remaining fields.

Implement this using two function clauses (one guarded on `is_list(compare_fields)`,
one matching `nil`). Use pattern matching / guards rather than an `if` inside a
single clause. The function must be pure — no processes, no side effects.

## The module

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

  @type record :: map()
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}

  @type matched_entry :: %{
          left: record(),
          right: record(),
          differences: diff_map()
        }

  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [record()],
          only_in_right: [record()]
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
  @spec reconcile([record()], [record()], keyword()) :: result()
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
  @spec index_by([record()], [atom()]) :: %{tuple() => record()}
  defp index_by(records, key_fields) do
    Map.new(records, fn record ->
      {composite_key(record, key_fields), record}
    end)
  end

  @spec composite_key(record(), [atom()]) :: tuple()
  defp composite_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  # Determines which fields to compare for a matched pair.
  # If compare_fields is explicitly provided, use it directly.
  # Otherwise, derive it as: (all keys in left ∪ right) minus key_fields.
  @spec resolve_compare_fields(record(), record(), [atom()], [atom()] | nil) :: [atom()]
  defp resolve_compare_fields(left, right, key_fields, compare_fields) do
    # TODO
  end

  # Compares `left` and `right` on the given fields using `==`.
  # Missing fields are treated as nil.
  @spec diff(record(), record(), [atom()]) :: diff_map()
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