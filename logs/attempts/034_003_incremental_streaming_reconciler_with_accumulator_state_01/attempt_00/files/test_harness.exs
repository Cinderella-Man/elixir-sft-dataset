defmodule ReconcilerTest do
  use ExUnit.Case, async: false

  defp add_all(state, side, records) do
    Enum.reduce(records, state, fn r, acc ->
      case side do
        :left -> Reconciler.put_left(acc, r)
        :right -> Reconciler.put_right(acc, r)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Incremental building
  # ---------------------------------------------------------------------------

  test "incrementally built reconciliation matches expected result" do
    state =
      Reconciler.new(key_fields: [:id])
      |> Reconciler.put_left(%{id: 1, name: "Alice"})
      |> Reconciler.put_left(%{id: 2, name: "Bob"})
      |> Reconciler.put_right(%{id: 1, name: "Alice"})
      |> Reconciler.put_right(%{id: 3, name: "Carol"})

    result = Reconciler.result(state)

    assert length(result.matched) == 1
    assert result.only_in_left == [%{id: 2, name: "Bob"}]
    assert result.only_in_right == [%{id: 3, name: "Carol"}]
  end

  test "matched entry reports differences and carries full records" do
    state =
      Reconciler.new(key_fields: [:id])
      |> Reconciler.put_left(%{id: 1, name: "Alice", role: "admin"})
      |> Reconciler.put_right(%{id: 1, name: "Alicia", role: "user"})

    [entry] = Reconciler.result(state).matched
    assert entry.left == %{id: 1, name: "Alice", role: "admin"}
    assert entry.right == %{id: 1, name: "Alicia", role: "user"}
    assert entry.differences == %{name: %{left: "Alice", right: "Alicia"}}
  end

  test "identical matched records have empty differences" do
    state =
      Reconciler.new(key_fields: [:id])
      |> Reconciler.put_left(%{id: 1, name: "Alice"})
      |> Reconciler.put_right(%{id: 1, name: "Alice"})

    [entry] = Reconciler.result(state).matched
    assert entry.differences == %{}
  end

  # ---------------------------------------------------------------------------
  # Last-write-wins per side
  # ---------------------------------------------------------------------------

  test "later put_left for same key overrides earlier one" do
    state =
      Reconciler.new(key_fields: [:id])
      |> Reconciler.put_left(%{id: 1, v: "a"})
      |> Reconciler.put_left(%{id: 1, v: "b"})

    result = Reconciler.result(state)
    assert result.only_in_left == [%{id: 1, v: "b"}]
    assert result.matched == []
  end

  test "last-write-wins applies on the right and feeds the diff" do
    state =
      Reconciler.new(key_fields: [:id])
      |> Reconciler.put_left(%{id: 1, score: 10})
      |> Reconciler.put_right(%{id: 1, score: 20})
      |> Reconciler.put_right(%{id: 1, score: 30})

    [entry] = Reconciler.result(state).matched
    assert entry.right == %{id: 1, score: 30}
    assert entry.differences == %{score: %{left: 10, right: 30}}
  end

  # ---------------------------------------------------------------------------
  # Interleaving order does not matter
  # ---------------------------------------------------------------------------

  test "interleaving order does not affect the result" do
    left = [%{id: 1, v: 1}, %{id: 2, v: 2}, %{id: 3, v: 3}]
    right = [%{id: 2, v: 2}, %{id: 3, v: 99}, %{id: 4, v: 4}]

    a =
      Reconciler.new(key_fields: [:id])
      |> add_all(:left, left)
      |> add_all(:right, right)

    b =
      Reconciler.new(key_fields: [:id])
      |> add_all(:right, right)
      |> add_all(:left, left)

    ra = Reconciler.result(a)
    rb = Reconciler.result(b)

    assert Enum.sort(ra.only_in_left) == Enum.sort(rb.only_in_left)
    assert Enum.sort(ra.only_in_right) == Enum.sort(rb.only_in_right)
    assert Enum.sort(ra.matched) == Enum.sort(rb.matched)
    assert length(ra.matched) == 2
  end

  # ---------------------------------------------------------------------------
  # compare_fields and missing fields
  # ---------------------------------------------------------------------------

  test "compare_fields restricts which fields are diffed" do
    state =
      Reconciler.new(key_fields: [:id], compare_fields: [:name])
      |> Reconciler.put_left(%{id: 1, name: "Alice", internal: "old"})
      |> Reconciler.put_right(%{id: 1, name: "Alice", internal: "new"})

    [entry] = Reconciler.result(state).matched
    assert entry.differences == %{}
  end

  test "omitted compare_fields diffs all non-key fields" do
    state =
      Reconciler.new(key_fields: [:id])
      |> Reconciler.put_left(%{id: 1, a: 1, b: 2})
      |> Reconciler.put_right(%{id: 1, a: 9, b: 2})

    [entry] = Reconciler.result(state).matched
    assert Map.has_key?(entry.differences, :a)
    refute Map.has_key?(entry.differences, :b)
    refute Map.has_key?(entry.differences, :id)
  end

  test "missing field diffs as nil" do
    state =
      Reconciler.new(key_fields: [:id])
      |> Reconciler.put_left(%{id: 1, score: 42})
      |> Reconciler.put_right(%{id: 1})

    [entry] = Reconciler.result(state).matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  # ---------------------------------------------------------------------------
  # Composite key + empty state
  # ---------------------------------------------------------------------------

  test "composite key matches only when all key fields are equal" do
    state =
      Reconciler.new(key_fields: [:org_id, :user_id])
      |> Reconciler.put_left(%{org_id: 1, user_id: 10, name: "Alice"})
      |> Reconciler.put_left(%{org_id: 1, user_id: 20, name: "Bob"})
      |> Reconciler.put_right(%{org_id: 1, user_id: 10, name: "Alice"})
      |> Reconciler.put_right(%{org_id: 2, user_id: 10, name: "Charlie"})

    result = Reconciler.result(state)
    assert length(result.matched) == 1
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1
  end

  test "empty state yields empty result" do
    result = Reconciler.new(key_fields: [:id]) |> Reconciler.result()
    assert result == %{matched: [], only_in_left: [], only_in_right: []}
  end
end
