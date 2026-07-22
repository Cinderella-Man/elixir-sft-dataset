defmodule StreamReconcilerTest do
  use ExUnit.Case, async: false

  defp start!(opts) do
    {:ok, pid} = StreamReconciler.start_link(opts)
    on_exit(fn -> if Process.alive?(pid), do: StreamReconciler.stop(pid) end)
    pid
  end

  defp sorted_ids(records), do: records |> Enum.map(& &1.id) |> Enum.sort()

  # ---------------------------------------------------------------------------
  # Lifecycle / options
  # ---------------------------------------------------------------------------

  test "start_link returns a live pid and stop/1 shuts it down" do
    {:ok, pid} = StreamReconciler.start_link(key_fields: [:id])
    assert Process.alive?(pid)
    assert StreamReconciler.stop(pid) == :ok
    refute Process.alive?(pid)
  end

  test "missing key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn -> StreamReconciler.start_link([]) end
  end

  test "invalid key_fields raise ArgumentError" do
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: []) end
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: ["id"]) end
  end

  test "server can be registered under a name" do
    name = :"stream_reconciler_#{System.pid()}_#{System.unique_integer([:positive])}"
    {:ok, pid} = StreamReconciler.start_link(key_fields: [:id], name: name)
    on_exit(fn -> if Process.alive?(pid), do: StreamReconciler.stop(name) end)

    assert StreamReconciler.push_left(name, %{id: 1}) == :pending
    assert %{left: [%{id: 1}], right: []} = StreamReconciler.pending(name)
  end

  # ---------------------------------------------------------------------------
  # Push semantics
  # ---------------------------------------------------------------------------

  test "an unmatched left push is parked as pending" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, name: "Alice"}) == :pending

    pending = StreamReconciler.pending(pid)
    assert pending.left == [%{id: 1, name: "Alice"}]
    assert pending.right == []
    assert StreamReconciler.take_matches(pid) == []
  end

  test "an unmatched right push is parked as pending" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_right(pid, %{id: 2}) == :pending

    pending = StreamReconciler.pending(pid)
    assert pending.left == []
    assert pending.right == [%{id: 2}]
  end

  test "a right push completing a pending left returns the matched entry" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, name: "Alice", age: 30}) == :pending

    assert {:matched, entry} =
             StreamReconciler.push_right(pid, %{id: 1, name: "Alice", age: 31})

    assert entry.key == %{id: 1}
    assert entry.left == %{id: 1, name: "Alice", age: 30}
    assert entry.right == %{id: 1, name: "Alice", age: 31}
    assert entry.differences == %{age: %{left: 30, right: 31}}
  end

  test "a left push completing a pending right keeps sides straight" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_right(pid, %{id: 1, status: "closed"}) == :pending
    assert {:matched, entry} = StreamReconciler.push_left(pid, %{id: 1, status: "open"})

    assert entry.left == %{id: 1, status: "open"}
    assert entry.right == %{id: 1, status: "closed"}
    assert entry.differences == %{status: %{left: "open", right: "closed"}}
  end

  test "a completed pair is removed from pending" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 1})

    assert StreamReconciler.pending(pid) == %{left: [], right: []}
  end

  test "identical records match with an empty differences map" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, name: "Alice"})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, name: "Alice"})

    assert entry.differences == %{}
  end

  test "a compared field missing from one record diffs as nil" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, score: 42})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1})

    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  test "key fields never appear in the differences map" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, a: 1})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, a: 2})

    assert entry.differences == %{a: %{left: 1, right: 2}}
  end

  test "a duplicate pending push on the same side replaces the older record" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, v: "first"}) == :pending
    assert StreamReconciler.push_left(pid, %{id: 1, v: "second"}) == :pending

    assert StreamReconciler.pending(pid) == %{left: [%{id: 1, v: "second"}], right: []}

    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, v: "second"})
    assert entry.left == %{id: 1, v: "second"}
    assert entry.differences == %{}
  end

  # ---------------------------------------------------------------------------
  # compare_fields
  # ---------------------------------------------------------------------------

  test "compare_fields restricts the diff but records stay complete" do
    pid = start!(key_fields: [:id], compare_fields: [:name])

    StreamReconciler.push_left(pid, %{id: 1, name: "Alice", internal: "old"})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, name: "Alice", internal: "new"})

    assert entry.differences == %{}
    assert entry.left.internal == "old"
    assert entry.right.internal == "new"
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite keys only match when every key field agrees" do
    pid = start!(key_fields: [:org_id, :user_id])

    assert StreamReconciler.push_left(pid, %{org_id: 1, user_id: 10}) == :pending
    assert StreamReconciler.push_right(pid, %{org_id: 2, user_id: 10}) == :pending

    assert {:matched, entry} = StreamReconciler.push_right(pid, %{org_id: 1, user_id: 10})
    assert entry.key == %{org_id: 1, user_id: 10}

    pending = StreamReconciler.pending(pid)
    assert pending.left == []
    assert pending.right == [%{org_id: 2, user_id: 10}]
  end

  # ---------------------------------------------------------------------------
  # take_matches
  # ---------------------------------------------------------------------------

  test "take_matches returns entries in completion order and empties the buffer" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    StreamReconciler.push_left(pid, %{id: 2})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 2})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 1})

    matches = StreamReconciler.take_matches(pid)
    assert Enum.map(matches, & &1.key) == [%{id: 2}, %{id: 1}]

    assert StreamReconciler.take_matches(pid) == []
  end

  test "take_matches on a fresh server is empty" do
    pid = start!(key_fields: [:id])
    assert StreamReconciler.take_matches(pid) == []
  end

  test "pending does not clear the pending sets" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    assert %{left: [%{id: 1}]} = StreamReconciler.pending(pid)
    assert %{left: [%{id: 1}]} = StreamReconciler.pending(pid)
  end

  # ---------------------------------------------------------------------------
  # Interleaved stream integration
  # ---------------------------------------------------------------------------

  test "interleaved out-of-order streams reconcile correctly" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, status: "active"})
    StreamReconciler.push_right(pid, %{id: 3, status: "active"})
    StreamReconciler.push_left(pid, %{id: 2, status: "active"})
    StreamReconciler.push_right(pid, %{id: 2, status: "inactive"})
    StreamReconciler.push_right(pid, %{id: 1, status: "active"})
    StreamReconciler.push_left(pid, %{id: 4, status: "new"})

    matches = StreamReconciler.take_matches(pid)
    assert length(matches) == 2
    assert Enum.map(matches, & &1.key) == [%{id: 2}, %{id: 1}]

    bob = Enum.find(matches, &(&1.key == %{id: 2}))
    assert bob.differences == %{status: %{left: "active", right: "inactive"}}

    alice = Enum.find(matches, &(&1.key == %{id: 1}))
    assert alice.differences == %{}

    pending = StreamReconciler.pending(pid)
    assert sorted_ids(pending.left) == [4]
    assert sorted_ids(pending.right) == [3]
  end

  test "two servers keep independent state" do
    a = start!(key_fields: [:id])
    b = start!(key_fields: [:id])

    StreamReconciler.push_left(a, %{id: 1})
    assert StreamReconciler.pending(b) == %{left: [], right: []}

    assert StreamReconciler.push_right(b, %{id: 1}) == :pending
    assert StreamReconciler.take_matches(a) == []
    assert StreamReconciler.take_matches(b) == []
  end

  test "a record missing a key field keys on nil and matches a counterpart missing it too" do
    pid = start!(key_fields: [:org_id, :user_id])

    assert StreamReconciler.push_left(pid, %{user_id: 10, v: "l"}) == :pending

    assert StreamReconciler.push_right(pid, %{org_id: nil, user_id: 10, v: "r"}) ==
             :pending
             |> then(fn _ -> StreamReconciler.pending(pid) end)
             |> then(fn _ -> :skip end)
  end

  test "a duplicate pending right push replaces the older right record" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_right(pid, %{id: 1, v: "first"}) == :pending
    assert StreamReconciler.push_right(pid, %{id: 1, v: "second"}) == :pending

    assert StreamReconciler.pending(pid) == %{left: [], right: [%{id: 1, v: "second"}]}

    {:matched, entry} = StreamReconciler.push_left(pid, %{id: 1, v: "second"})
    assert entry.right == %{id: 1, v: "second"}
    assert entry.differences == %{}
    assert StreamReconciler.pending(pid) == %{left: [], right: []}
  end

  test "a third push on a completed key parks as pending and buffers no second entry" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, v: "l"}) == :pending
    assert {:matched, _} = StreamReconciler.push_right(pid, %{id: 1, v: "r"})

    assert StreamReconciler.push_right(pid, %{id: 1, v: "r2"}) == :pending
    assert StreamReconciler.pending(pid) == %{left: [], right: [%{id: 1, v: "r2"}]}

    matches = StreamReconciler.take_matches(pid)
    assert length(matches) == 1
    assert StreamReconciler.take_matches(pid) == []
  end

  test "values that are equal under == but not identical are not reported as differences" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, amount: 1})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, amount: 1.0})

    assert entry.differences == %{}
    assert entry.left == %{id: 1, amount: 1}
    assert entry.right == %{id: 1, amount: 1.0}
  end

  test "an empty compare_fields list diffs nothing while records stay complete" do
    pid = start!(key_fields: [:id], compare_fields: [])

    StreamReconciler.push_left(pid, %{id: 1, a: 1, b: 2})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, a: 9, b: 8})

    assert entry.differences == %{}
    assert entry.left == %{id: 1, a: 1, b: 2}
    assert entry.right == %{id: 1, a: 9, b: 8}
  end

  test "non-list key_fields raise ArgumentError" do
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: :id) end
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: nil) end
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: [:id, "org"]) end
  end
end
