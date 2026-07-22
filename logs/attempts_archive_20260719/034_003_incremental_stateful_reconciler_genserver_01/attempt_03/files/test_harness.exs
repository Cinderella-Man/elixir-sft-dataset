defmodule ReconcilerTest do
  use ExUnit.Case, async: false

  defp start_server(opts) do
    {:ok, pid} = Reconciler.start_link(opts)
    pid
  end

  defp matched_for(result, id) do
    Enum.find(result.matched, fn e -> e.left.id == id end)
  end

  test "start_link raises when :key_fields is missing" do
    assert_raise ArgumentError, fn -> Reconciler.start_link([]) end
  end

  test "put functions return :ok" do
    pid = start_server(key_fields: [:id])
    assert Reconciler.put_left(pid, %{id: 1}) == :ok
    assert Reconciler.put_right(pid, %{id: 1}) == :ok
  end

  test "records fed to both sides appear in :matched" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1, name: "Alice"})
    Reconciler.put_left(pid, %{id: 2, name: "Bob"})
    Reconciler.put_right(pid, %{id: 1, name: "Alice"})
    Reconciler.put_right(pid, %{id: 2, name: "Bob"})

    result = Reconciler.reconcile(pid)

    assert length(result.matched) == 2
    assert result.only_in_left == []
    assert result.only_in_right == []
  end

  test "records only on one side are reported" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1})
    Reconciler.put_left(pid, %{id: 2})
    Reconciler.put_right(pid, %{id: 1})
    Reconciler.put_right(pid, %{id: 3})

    result = Reconciler.reconcile(pid)

    assert result.only_in_left == [%{id: 2}]
    assert result.only_in_right == [%{id: 3}]
    assert length(result.matched) == 1
  end

  test "empty server reconciles to an empty result" do
    pid = start_server(key_fields: [:id])

    assert Reconciler.reconcile(pid) ==
             %{matched: [], only_in_left: [], only_in_right: []}
  end

  test "identical matched records have empty differences" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1, name: "Alice", age: 30})
    Reconciler.put_right(pid, %{id: 1, name: "Alice", age: 30})

    [entry] = Reconciler.reconcile(pid).matched
    assert entry.differences == %{}
  end

  test "differing fields are reported" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1, name: "Alice", age: 30})
    Reconciler.put_right(pid, %{id: 1, name: "Alicia", age: 31})

    [entry] = Reconciler.reconcile(pid).matched

    assert entry.differences == %{
             name: %{left: "Alice", right: "Alicia"},
             age: %{left: 30, right: 31}
           }
  end

  test "matched entry carries full original records" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1, name: "Alice", role: "admin"})
    Reconciler.put_right(pid, %{id: 1, name: "Alice", role: "user"})

    [entry] = Reconciler.reconcile(pid).matched
    assert entry.left == %{id: 1, name: "Alice", role: "admin"}
    assert entry.right == %{id: 1, name: "Alice", role: "user"}
  end

  test "putting the same key again replaces the previous record (last write wins)" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1, name: "Alice", status: "old"})
    Reconciler.put_left(pid, %{id: 1, name: "Alice", status: "new"})
    Reconciler.put_right(pid, %{id: 1, name: "Alice", status: "new"})

    result = Reconciler.reconcile(pid)
    assert length(result.matched) == 1
    [entry] = result.matched
    assert entry.left == %{id: 1, name: "Alice", status: "new"}
    assert entry.differences == %{}
  end

  test "reconcile does not consume state and is repeatable" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1})
    Reconciler.put_right(pid, %{id: 1})

    first = Reconciler.reconcile(pid)
    second = Reconciler.reconcile(pid)
    assert first == second
    assert length(second.matched) == 1
  end

  test "incremental arrivals change the result over time" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1})

    before = Reconciler.reconcile(pid)
    assert before.only_in_left == [%{id: 1}]
    assert before.matched == []

    Reconciler.put_right(pid, %{id: 1})
    after_put = Reconciler.reconcile(pid)
    assert after_put.only_in_left == []
    assert length(after_put.matched) == 1
  end

  test "reset clears both sides" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1})
    Reconciler.put_right(pid, %{id: 1})
    assert Reconciler.reset(pid) == :ok

    assert Reconciler.reconcile(pid) ==
             %{matched: [], only_in_left: [], only_in_right: []}
  end

  test "compare_fields restricts which fields are diffed" do
    pid = start_server(key_fields: [:id], compare_fields: [:name])
    Reconciler.put_left(pid, %{id: 1, name: "Alice", internal_ref: "old"})
    Reconciler.put_right(pid, %{id: 1, name: "Alice", internal_ref: "new"})

    [entry] = Reconciler.reconcile(pid).matched
    assert entry.differences == %{}
  end

  test "composite key matches only when all key fields are equal" do
    pid = start_server(key_fields: [:org_id, :user_id])
    Reconciler.put_left(pid, %{org_id: 1, user_id: 10, name: "Alice"})
    Reconciler.put_left(pid, %{org_id: 1, user_id: 20, name: "Bob"})
    Reconciler.put_right(pid, %{org_id: 1, user_id: 10, name: "Alice"})
    Reconciler.put_right(pid, %{org_id: 2, user_id: 10, name: "Charlie"})

    result = Reconciler.reconcile(pid)
    assert length(result.matched) == 1
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1
  end

  test "a compared field missing from one record diffs as nil" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1, score: 42})
    Reconciler.put_right(pid, %{id: 1})

    [entry] = Reconciler.reconcile(pid).matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  test "mixed integration scenario" do
    pid = start_server(key_fields: [:id])
    Reconciler.put_left(pid, %{id: 1, name: "Alice", status: "active"})
    Reconciler.put_left(pid, %{id: 2, name: "Bob", status: "active"})
    Reconciler.put_left(pid, %{id: 3, name: "Charlie", status: "inactive"})
    Reconciler.put_right(pid, %{id: 1, name: "Alice", status: "active"})
    Reconciler.put_right(pid, %{id: 2, name: "Bob", status: "inactive"})
    Reconciler.put_right(pid, %{id: 4, name: "Diana", status: "active"})

    result = Reconciler.reconcile(pid)

    assert length(result.matched) == 2
    assert hd(result.only_in_left).id == 3
    assert hd(result.only_in_right).id == 4

    alice = matched_for(result, 1)
    assert alice.differences == %{}

    bob = matched_for(result, 2)
    assert bob.differences == %{status: %{left: "active", right: "inactive"}}
  end
end
