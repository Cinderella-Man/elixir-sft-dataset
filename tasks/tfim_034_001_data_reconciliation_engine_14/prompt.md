# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule ReconcilerTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Basic matching
  # ---------------------------------------------------------------------------

  test "records present in both lists appear in :matched" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert length(result.matched) == 2
    assert result.only_in_left == []
    assert result.only_in_right == []
  end

  test "records only in left appear in :only_in_left" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 1}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.only_in_left == [%{id: 2}]
    assert result.only_in_right == []
    assert length(result.matched) == 1
  end

  test "records only in right appear in :only_in_right" do
    left = [%{id: 1}]
    right = [%{id: 1}, %{id: 3}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.only_in_right == [%{id: 3}]
    assert result.only_in_left == []
    assert length(result.matched) == 1
  end

  test "completely disjoint lists produce no matches" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 3}, %{id: 4}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert length(result.only_in_left) == 2
    assert length(result.only_in_right) == 2
  end

  test "empty left list" do
    left = []
    right = [%{id: 1}, %{id: 2}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert result.only_in_left == []
    assert length(result.only_in_right) == 2
  end

  test "empty right list" do
    left = [%{id: 1}, %{id: 2}]
    right = []

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert result.only_in_right == []
    assert length(result.only_in_left) == 2
  end

  test "both lists empty" do
    result = Reconciler.reconcile([], [], key_fields: [:id])
    assert result == %{matched: [], only_in_left: [], only_in_right: []}
  end

  # ---------------------------------------------------------------------------
  # Field-level diff
  # ---------------------------------------------------------------------------

  test "identical matched records have empty differences map" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alice", age: 30}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "differing fields are reported correctly" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alicia", age: 31}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched

    assert entry.differences == %{
             name: %{left: "Alice", right: "Alicia"},
             age: %{left: 30, right: 31}
           }
  end

  test "matched entry carries full original records regardless of diffs" do
    left = [%{id: 1, name: "Alice", role: "admin"}]
    right = [%{id: 1, name: "Alice", role: "user"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.left == %{id: 1, name: "Alice", role: "admin"}
    assert entry.right == %{id: 1, name: "Alice", role: "user"}
  end

  # ---------------------------------------------------------------------------
  # compare_fields option
  # ---------------------------------------------------------------------------

  test "compare_fields restricts which fields are diffed" do
    left = [%{id: 1, name: "Alice", internal_ref: "old"}]
    right = [%{id: 1, name: "Alice", internal_ref: "new"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    # :internal_ref differs but is excluded from comparison
    assert entry.differences == %{}
  end

  test "compare_fields still diffs the specified fields" do
    left = [%{id: 1, name: "Alice", score: 10}]
    right = [%{id: 1, name: "Bob", score: 10}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    assert entry.differences == %{name: %{left: "Alice", right: "Bob"}}
  end

  test "when compare_fields is omitted, all non-key fields are compared" do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite key matches only when all key fields are equal" do
    left = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 1, user_id: 20, name: "Bob"}
    ]

    right = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      # same user_id, different org
      %{org_id: 2, user_id: 10, name: "Charlie"}
    ]

    result = Reconciler.reconcile(left, right, key_fields: [:org_id, :user_id])

    assert length(result.matched) == 1
    [entry] = result.matched
    assert entry.left.name == "Alice"

    # Bob (org 1, user 20)
    assert length(result.only_in_left) == 1
    # Charlie (org 2, user 10)
    assert length(result.only_in_right) == 1
  end

  # ---------------------------------------------------------------------------
  # Missing fields treated as nil
  # ---------------------------------------------------------------------------

  test "a field missing from one record is diffed as nil vs present value" do
    left = [%{id: 1, score: 42}]
    # :score absent
    right = [%{id: 1}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  # ---------------------------------------------------------------------------
  # Mixed scenario (integration)
  # ---------------------------------------------------------------------------

  test "mixed scenario with matches, diffs, and uniques" do
    left = [
      %{id: 1, name: "Alice", status: "active"},
      %{id: 2, name: "Bob", status: "active"},
      %{id: 3, name: "Charlie", status: "inactive"}
    ]

    right = [
      # identical
      %{id: 1, name: "Alice", status: "active"},
      # status differs
      %{id: 2, name: "Bob", status: "inactive"},
      # only in right
      %{id: 4, name: "Diana", status: "active"}
    ]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    # Totals
    assert length(result.matched) == 2
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1

    # Only-lists
    assert hd(result.only_in_left).id == 3
    assert hd(result.only_in_right).id == 4

    # Matched record with no diff
    alice = Enum.find(result.matched, &(&1.left.id == 1))
    assert alice.differences == %{}

    # Matched record with diff
    bob = Enum.find(result.matched, &(&1.left.id == 2))
    assert bob.differences == %{status: %{left: "active", right: "inactive"}}
  end

  test "values equal under == are not reported as differences" do
    left = [%{id: 1, score: 1, ratio: 2.0}]
    right = [%{id: 1, score: 1.0, ratio: 2}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "compare_fields field absent from both records yields no difference" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Alice"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name, :nowhere_field]
      )

    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "explicitly compared field absent from left record diffs as nil vs value" do
    left = [%{id: 1}]
    right = [%{id: 1, score: 7}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:score]
      )

    [entry] = result.matched
    assert entry.differences == %{score: %{left: nil, right: 7}}
  end

  test "matched entry keeps full records when compare_fields excludes differing fields" do
    left = [%{id: 1, name: "Alice", internal_ref: "old", extra: 1}]
    right = [%{id: 1, name: "Alice", internal_ref: "new", extra: 2}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    assert entry.differences == %{}
    assert entry.left == %{id: 1, name: "Alice", internal_ref: "old", extra: 1}
    assert entry.right == %{id: 1, name: "Alice", internal_ref: "new", extra: 2}
  end

  test "composite key with equal first field but differing second field never matches" do
    left = [%{org_id: 1, user_id: 10, name: "Alice"}]
    right = [%{org_id: 1, user_id: 11, name: "Alice"}]

    result = Reconciler.reconcile(left, right, key_fields: [:org_id, :user_id])

    assert result.matched == []
    assert result.only_in_left == [%{org_id: 1, user_id: 10, name: "Alice"}]
    assert result.only_in_right == [%{org_id: 1, user_id: 11, name: "Alice"}]
  end

  # ---------------------------------------------------------------------------
  # :key_fields validation (required option)
  # ---------------------------------------------------------------------------

  test "an empty :key_fields list raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], key_fields: [])
    end
  end

  test "a non-list :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], key_fields: :id)
    end
  end

  test "a :key_fields list containing non-atoms raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], key_fields: ["id"])
    end
  end

  test "a nil :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], key_fields: nil)
    end
  end

  test "omitting :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], [])
    end
  end
end
```
