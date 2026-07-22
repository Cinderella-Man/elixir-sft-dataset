defmodule ReconcilerServerTest do
  use ExUnit.Case, async: false

  defp start(opts) do
    {:ok, pid} = ReconcilerServer.start_link(opts)
    pid
  end

  test "records put on both sides with equal keys appear in :matched" do
    s = start(key_fields: [:id])
    assert :ok == ReconcilerServer.put_left(s, %{id: 1, name: "Alice"})
    assert :ok == ReconcilerServer.put_right(s, %{id: 1, name: "Alice"})

    r = ReconcilerServer.reconcile(s)

    assert length(r.matched) == 1
    assert r.only_in_left == []
    assert r.only_in_right == []
  end

  test "records only on one side land in the correct only-list" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1})
    :ok = ReconcilerServer.put_left(s, %{id: 2})
    :ok = ReconcilerServer.put_right(s, %{id: 1})
    :ok = ReconcilerServer.put_right(s, %{id: 3})

    r = ReconcilerServer.reconcile(s)

    assert length(r.matched) == 1
    assert r.only_in_left == [%{id: 2}]
    assert r.only_in_right == [%{id: 3}]
  end

  test "differences are reported for matched records" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1, name: "Alice", age: 30})
    :ok = ReconcilerServer.put_right(s, %{id: 1, name: "Alicia", age: 30})

    [entry] = ReconcilerServer.reconcile(s).matched

    assert entry.differences == %{name: %{left: "Alice", right: "Alicia"}}
  end

  test "identical matched records have an empty differences map" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1, name: "Alice"})
    :ok = ReconcilerServer.put_right(s, %{id: 1, name: "Alice"})

    [entry] = ReconcilerServer.reconcile(s).matched
    assert entry.differences == %{}
  end

  test "putting the same key on one side twice replaces the earlier record" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1, name: "Old"})
    :ok = ReconcilerServer.put_left(s, %{id: 1, name: "New"})
    :ok = ReconcilerServer.put_right(s, %{id: 1, name: "New"})

    [entry] = ReconcilerServer.reconcile(s).matched
    assert entry.left == %{id: 1, name: "New"}
    assert entry.differences == %{}
  end

  test "reconcile reflects incremental state across multiple calls" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1})

    r1 = ReconcilerServer.reconcile(s)
    assert r1.matched == []
    assert r1.only_in_left == [%{id: 1}]

    :ok = ReconcilerServer.put_right(s, %{id: 1})
    r2 = ReconcilerServer.reconcile(s)
    assert length(r2.matched) == 1
    assert r2.only_in_left == []
  end

  test "delete_left removes a left record" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1, name: "Alice"})
    :ok = ReconcilerServer.put_right(s, %{id: 1, name: "Alice"})

    assert length(ReconcilerServer.reconcile(s).matched) == 1

    assert :ok == ReconcilerServer.delete_left(s, %{id: 1})
    r = ReconcilerServer.reconcile(s)
    assert r.matched == []
    assert r.only_in_right == [%{id: 1, name: "Alice"}]
  end

  test "delete_right removes a right record" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1})
    :ok = ReconcilerServer.put_right(s, %{id: 1})

    assert :ok == ReconcilerServer.delete_right(s, %{id: 1})
    r = ReconcilerServer.reconcile(s)
    assert r.only_in_left == [%{id: 1}]
    assert r.matched == []
  end

  test "deleting an absent key is a no-op returning :ok" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1})

    assert :ok == ReconcilerServer.delete_left(s, %{id: 999})
    assert ReconcilerServer.reconcile(s).only_in_left == [%{id: 1}]
  end

  test "composite key matches only when all key fields are equal" do
    s = start(key_fields: [:org_id, :user_id])
    :ok = ReconcilerServer.put_left(s, %{org_id: 1, user_id: 10, name: "Alice"})
    :ok = ReconcilerServer.put_left(s, %{org_id: 1, user_id: 20, name: "Bob"})
    :ok = ReconcilerServer.put_right(s, %{org_id: 1, user_id: 10, name: "Alice"})
    :ok = ReconcilerServer.put_right(s, %{org_id: 2, user_id: 10, name: "Charlie"})

    r = ReconcilerServer.reconcile(s)

    assert length(r.matched) == 1
    assert length(r.only_in_left) == 1
    assert length(r.only_in_right) == 1
    [entry] = r.matched
    assert entry.left.name == "Alice"
  end

  test "compare_fields restricts which fields are diffed" do
    s = start(key_fields: [:id], compare_fields: [:name])
    :ok = ReconcilerServer.put_left(s, %{id: 1, name: "Alice", internal_ref: "old"})
    :ok = ReconcilerServer.put_right(s, %{id: 1, name: "Alice", internal_ref: "new"})

    [entry] = ReconcilerServer.reconcile(s).matched
    assert entry.differences == %{}
  end

  test "a field missing from one record is diffed as nil vs present value" do
    s = start(key_fields: [:id])
    :ok = ReconcilerServer.put_left(s, %{id: 1, score: 42})
    :ok = ReconcilerServer.put_right(s, %{id: 1})

    [entry] = ReconcilerServer.reconcile(s).matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  test "invalid :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn -> ReconcilerServer.start_link([]) end
    assert_raise ArgumentError, fn -> ReconcilerServer.start_link(key_fields: []) end
  end
end
