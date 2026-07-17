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
    left = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 1, user_id: 20, name: "Bob"}
    ]

    right = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 2, user_id: 10, name: "Charlie"}
    ]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:org_id, :user_id])

    [entry] = report.one_to_one
    assert entry.key == %{org_id: 1, user_id: 10}
    assert length(report.only_in_left) == 1
    assert length(report.only_in_right) == 1
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

  test "key values equal under == match even when their terms are not identical" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1.0, name: "Alice"}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert [entry] = report.one_to_one
    assert entry.left == %{id: 1, name: "Alice"}
    assert entry.right == %{id: 1.0, name: "Alice"}
    assert report.only_in_left == []
    assert report.only_in_right == []
  end

  test "the report map holds exactly the six documented keys" do
    left = [%{id: 1, v: 1}, %{id: 2, v: 1}, %{id: 2, v: 2}]
    right = [%{id: 1, v: 9}, %{id: 3, v: 1}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert Enum.sort(Map.keys(report)) ==
             Enum.sort([
               :one_to_one,
               :one_to_many,
               :many_to_one,
               :many_to_many,
               :only_in_left,
               :only_in_right
             ])
  end

  test "an explicit nil compare_fields compares every non-key field of the pair" do
    left = [%{id: 1, name: "Alice", only_left: 1}]
    right = [%{id: 1, name: "Alicia", only_right: 2}]

    report =
      MultiKeyReconciler.classify(left, right, key_fields: [:id], compare_fields: nil)

    assert [entry] = report.one_to_one

    assert entry.differences == %{
             name: %{left: "Alice", right: "Alicia"},
             only_left: %{left: 1, right: nil},
             only_right: %{left: nil, right: 2}
           }
  end

  test "a key_fields value that is not a list at all raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiKeyReconciler.classify([%{id: 1}], [%{id: 1}], key_fields: :id)
    end
  end

  test "compare_fields naming a field absent from both records reports no difference" do
    left = [%{id: 1, score: 42}]
    right = [%{id: 1}]

    report =
      MultiKeyReconciler.classify(left, right,
        key_fields: [:id],
        compare_fields: [:score, :ghost]
      )

    assert [entry] = report.one_to_one
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  test "many_to_one and many_to_many entries carry no differences map" do
    left = [%{id: 1, v: 1}, %{id: 1, v: 2}, %{id: 2, v: 1}, %{id: 2, v: 2}]
    right = [%{id: 1, v: 9}, %{id: 2, v: 8}, %{id: 2, v: 7}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert [m_to_1] = report.many_to_one
    refute Map.has_key?(m_to_1, :differences)

    assert [m_to_m] = report.many_to_many
    refute Map.has_key?(m_to_m, :differences)
    assert m_to_m.right == [%{id: 2, v: 8}, %{id: 2, v: 7}]
  end
end
