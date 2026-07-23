# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule MultiKeyReconcilerTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # One-to-one
  # ---------------------------------------------------------------------------

  test "unique keys on both sides yield one_to_one entries" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert length(report.one_to_one) == 2
    assert report.one_to_many == []
    assert report.many_to_one == []
    assert report.many_to_many == []
    assert report.only_in_left == []
    assert report.only_in_right == []
  end

  test "one_to_one entry carries key map, full records and differences" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alicia", age: 30}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.one_to_one
    assert entry.key == %{id: 1}
    assert entry.left == %{id: 1, name: "Alice", age: 30}
    assert entry.right == %{id: 1, name: "Alicia", age: 30}
    assert entry.differences == %{name: %{left: "Alice", right: "Alicia"}}
  end

  test "identical one_to_one pair has an empty differences map" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Alice"}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.one_to_one
    assert entry.differences == %{}
  end

  test "a compared field missing from one record diffs as nil" do
    left = [%{id: 1, score: 42}]
    right = [%{id: 1}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.one_to_one
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  test "compare_fields restricts the diff but records stay complete" do
    left = [%{id: 1, name: "Alice", internal: "old"}]
    right = [%{id: 1, name: "Alice", internal: "new"}]

    report =
      MultiKeyReconciler.classify(left, right, key_fields: [:id], compare_fields: [:name])

    [entry] = report.one_to_one
    assert entry.differences == %{}
    assert entry.left.internal == "old"
    assert entry.right.internal == "new"
  end

  test "key fields are never reported as differences by default" do
    left = [%{id: 1, a: 1, b: 2}]
    right = [%{id: 1, a: 9, b: 2}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.one_to_one
    assert entry.differences == %{a: %{left: 1, right: 9}}
  end

  # ---------------------------------------------------------------------------
  # Ambiguous cardinalities
  # ---------------------------------------------------------------------------

  test "one left and many right records produce a one_to_many entry" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Alice A"}, %{id: 1, name: "Alice B"}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert report.one_to_one == []
    [entry] = report.one_to_many
    assert entry.key == %{id: 1}
    assert entry.left == %{id: 1, name: "Alice"}
    assert entry.right == [%{id: 1, name: "Alice A"}, %{id: 1, name: "Alice B"}]
    refute Map.has_key?(entry, :differences)
  end

  test "many left and one right record produce a many_to_one entry" do
    left = [%{id: 7, v: 1}, %{id: 7, v: 2}]
    right = [%{id: 7, v: 3}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.many_to_one
    assert entry.key == %{id: 7}
    assert entry.left == [%{id: 7, v: 1}, %{id: 7, v: 2}]
    assert entry.right == %{id: 7, v: 3}
    assert report.one_to_one == []
    assert report.one_to_many == []
  end

  test "many records on both sides produce a many_to_many entry" do
    left = [%{id: 9, v: 1}, %{id: 9, v: 2}]
    right = [%{id: 9, v: 3}, %{id: 9, v: 4}, %{id: 9, v: 5}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.many_to_many
    assert entry.key == %{id: 9}
    assert length(entry.left) == 2
    assert length(entry.right) == 3
    assert entry.left == [%{id: 9, v: 1}, %{id: 9, v: 2}]
  end

  # ---------------------------------------------------------------------------
  # Only-in-left / only-in-right groups
  # ---------------------------------------------------------------------------

  test "keys absent from the other side are grouped under only_in_left / only_in_right" do
    left = [%{id: 1}, %{id: 2, tag: "a"}, %{id: 2, tag: "b"}]
    right = [%{id: 3}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert length(report.only_in_left) == 2
    assert length(report.only_in_right) == 1

    dup = Enum.find(report.only_in_left, &(&1.key == %{id: 2}))
    assert dup.records == [%{id: 2, tag: "a"}, %{id: 2, tag: "b"}]

    [only_right] = report.only_in_right
    assert only_right.key == %{id: 3}
    assert only_right.records == [%{id: 3}]
  end

  test "empty inputs produce an empty report" do
    report = MultiKeyReconciler.classify([], [], key_fields: [:id])

    assert report.one_to_one == []
    assert report.one_to_many == []
    assert report.many_to_one == []
    assert report.many_to_many == []
    assert report.only_in_left == []
    assert report.only_in_right == []
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite keys match only when all key fields are equal" do
    # TODO
  end

  test "a record missing a key field keys on nil" do
    left = [%{user_id: 10, v: 1}]
    right = [%{org_id: nil, user_id: 10, v: 2}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:org_id, :user_id])

    [entry] = report.one_to_one
    assert entry.key == %{org_id: nil, user_id: 10}
  end

  # ---------------------------------------------------------------------------
  # Invalid options
  # ---------------------------------------------------------------------------

  test "missing key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn -> MultiKeyReconciler.classify([], [], []) end
  end

  test "empty key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiKeyReconciler.classify([], [], key_fields: [])
    end
  end

  test "non-atom key_fields raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiKeyReconciler.classify([], [], key_fields: ["id"])
    end
  end

  # ---------------------------------------------------------------------------
  # counts/1
  # ---------------------------------------------------------------------------

  test "counts reports entry counts per category plus ambiguous total" do
    left = [
      %{id: 1, v: 1},
      %{id: 2, v: 1},
      %{id: 3, v: 1},
      %{id: 3, v: 2},
      %{id: 4, v: 1},
      %{id: 4, v: 2},
      %{id: 5, v: 1}
    ]

    right = [
      %{id: 1, v: 1},
      %{id: 2, v: 1},
      %{id: 2, v: 2},
      %{id: 3, v: 9},
      %{id: 4, v: 8},
      %{id: 4, v: 7},
      %{id: 6, v: 1}
    ]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])
    counts = MultiKeyReconciler.counts(report)

    # id 1 -> 1:1, id 2 -> 1:many, id 3 -> many:1, id 4 -> many:many,
    # id 5 -> only left, id 6 -> only right
    assert counts.one_to_one == 1
    assert counts.one_to_many == 1
    assert counts.many_to_one == 1
    assert counts.many_to_many == 1
    assert counts.only_in_left == 1
    assert counts.only_in_right == 1
    assert counts.ambiguous == 3
  end

  test "counts on an empty report is all zeros" do
    counts = MultiKeyReconciler.counts(MultiKeyReconciler.classify([], [], key_fields: [:id]))

    assert counts == %{
             one_to_one: 0,
             one_to_many: 0,
             many_to_one: 0,
             many_to_many: 0,
             only_in_left: 0,
             only_in_right: 0,
             ambiguous: 0
           }
  end

  # ---------------------------------------------------------------------------
  # Integration
  # ---------------------------------------------------------------------------

  test "mixed scenario" do
    left = [
      %{id: 1, name: "Alice", status: "active"},
      %{id: 2, name: "Bob", status: "active"},
      %{id: 2, name: "Bobby", status: "active"},
      %{id: 3, name: "Charlie", status: "inactive"}
    ]

    right = [
      %{id: 1, name: "Alice", status: "suspended"},
      %{id: 2, name: "Bob", status: "active"},
      %{id: 4, name: "Diana", status: "active"}
    ]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [alice] = report.one_to_one
    assert alice.key == %{id: 1}
    assert alice.differences == %{status: %{left: "active", right: "suspended"}}

    [bobs] = report.many_to_one
    assert length(bobs.left) == 2
    assert bobs.right.name == "Bob"

    [charlie] = report.only_in_left
    assert charlie.records == [%{id: 3, name: "Charlie", status: "inactive"}]

    [diana] = report.only_in_right
    assert diana.key == %{id: 4}

    counts = MultiKeyReconciler.counts(report)
    assert counts.ambiguous == 1
  end
end
```
