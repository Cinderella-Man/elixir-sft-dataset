defmodule StreamingReconcilerTest do
  use ExUnit.Case, async: false

  defp start(opts) do
    {:ok, pid} = StreamingReconciler.start_link(opts)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  test "a fresh server snapshots to an empty reconciliation" do
    pid = start(key_fields: [:id])

    assert StreamingReconciler.snapshot(pid) == %{
             matched: [],
             only_in_left: [],
             only_in_right: []
           }
  end

  test "ingest functions return :ok" do
    pid = start(key_fields: [:id])
    assert StreamingReconciler.add_left(pid, %{id: 1}) == :ok
    assert StreamingReconciler.add_right(pid, %{id: 1}) == :ok
  end

  test "snapshot reflects matched and only-in-side records" do
    pid = start(key_fields: [:id])
    :ok = StreamingReconciler.add_left(pid, %{id: 1, name: "Alice"})
    :ok = StreamingReconciler.add_left(pid, %{id: 2, name: "Bob"})
    :ok = StreamingReconciler.add_right(pid, %{id: 1, name: "Alice"})
    :ok = StreamingReconciler.add_right(pid, %{id: 3, name: "Carol"})

    snap = StreamingReconciler.snapshot(pid)

    assert length(snap.matched) == 1
    assert snap.only_in_left == [%{id: 2, name: "Bob"}]
    assert snap.only_in_right == [%{id: 3, name: "Carol"}]
  end

  test "differences are reported for matched pairs" do
    pid = start(key_fields: [:id])
    :ok = StreamingReconciler.add_left(pid, %{id: 1, name: "Alice", age: 30})
    :ok = StreamingReconciler.add_right(pid, %{id: 1, name: "Alice", age: 31})

    [entry] = StreamingReconciler.snapshot(pid).matched
    assert entry.differences == %{age: %{left: 30, right: 31}}
    assert entry.left == %{id: 1, name: "Alice", age: 30}
    assert entry.right == %{id: 1, name: "Alice", age: 31}
  end

  test "identical matched records have an empty differences map" do
    pid = start(key_fields: [:id])
    :ok = StreamingReconciler.add_left(pid, %{id: 1, name: "Alice"})
    :ok = StreamingReconciler.add_right(pid, %{id: 1, name: "Alice"})

    [entry] = StreamingReconciler.snapshot(pid).matched
    assert entry.differences == %{}
  end

  test "a later right record turns an only-in-left key into a match" do
    pid = start(key_fields: [:id])
    :ok = StreamingReconciler.add_left(pid, %{id: 1, name: "Alice"})

    first = StreamingReconciler.snapshot(pid)
    assert first.only_in_left == [%{id: 1, name: "Alice"}]
    assert first.matched == []

    :ok = StreamingReconciler.add_right(pid, %{id: 1, name: "Alice"})

    second = StreamingReconciler.snapshot(pid)
    assert second.only_in_left == []
    assert length(second.matched) == 1
  end

  test "re-ingesting the same key on a side keeps the most recent record" do
    pid = start(key_fields: [:id])
    :ok = StreamingReconciler.add_left(pid, %{id: 1, name: "Old"})
    :ok = StreamingReconciler.add_left(pid, %{id: 1, name: "New"})
    :ok = StreamingReconciler.add_right(pid, %{id: 1, name: "New"})

    [entry] = StreamingReconciler.snapshot(pid).matched
    assert entry.left == %{id: 1, name: "New"}
    assert entry.differences == %{}
  end

  test "a field missing from one matched record diffs as nil" do
    pid = start(key_fields: [:id])
    :ok = StreamingReconciler.add_left(pid, %{id: 1, score: 42})
    :ok = StreamingReconciler.add_right(pid, %{id: 1})

    [entry] = StreamingReconciler.snapshot(pid).matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  test "compare_fields restricts which fields are diffed" do
    pid = start(key_fields: [:id], compare_fields: [:name])
    :ok = StreamingReconciler.add_left(pid, %{id: 1, name: "Alice", internal_ref: "old"})
    :ok = StreamingReconciler.add_right(pid, %{id: 1, name: "Alice", internal_ref: "new"})

    [entry] = StreamingReconciler.snapshot(pid).matched
    assert entry.differences == %{}
  end

  test "composite key matches only when all key fields are equal" do
    pid = start(key_fields: [:org_id, :user_id])
    :ok = StreamingReconciler.add_left(pid, %{org_id: 1, user_id: 10, name: "Alice"})
    :ok = StreamingReconciler.add_left(pid, %{org_id: 1, user_id: 20, name: "Bob"})
    :ok = StreamingReconciler.add_right(pid, %{org_id: 1, user_id: 10, name: "Alice"})
    :ok = StreamingReconciler.add_right(pid, %{org_id: 2, user_id: 10, name: "Charlie"})

    snap = StreamingReconciler.snapshot(pid)
    assert length(snap.matched) == 1
    assert length(snap.only_in_left) == 1
    assert length(snap.only_in_right) == 1
  end

  test "reset discards all ingested records" do
    pid = start(key_fields: [:id])
    :ok = StreamingReconciler.add_left(pid, %{id: 1})
    :ok = StreamingReconciler.add_right(pid, %{id: 1})
    assert length(StreamingReconciler.snapshot(pid).matched) == 1

    assert StreamingReconciler.reset(pid) == :ok

    assert StreamingReconciler.snapshot(pid) == %{
             matched: [],
             only_in_left: [],
             only_in_right: []
           }
  end
end
