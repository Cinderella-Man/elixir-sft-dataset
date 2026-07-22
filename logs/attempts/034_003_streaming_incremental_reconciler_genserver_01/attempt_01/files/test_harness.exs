defmodule StreamReconcilerTest do
  use ExUnit.Case, async: false

  defp start(opts) do
    {:ok, pid} = StreamReconciler.start_link(opts)
    pid
  end

  # ---------------------------------------------------------------------------
  # Startup and pushes
  # ---------------------------------------------------------------------------

  test "start_link returns {:ok, pid} and pushes return :ok" do
    {:ok, pid} = StreamReconciler.start_link(key_fields: [:id])
    assert is_pid(pid)
    assert StreamReconciler.push_left(pid, %{id: 1}) == :ok
    assert StreamReconciler.push_right(pid, %{id: 1}) == :ok
    StreamReconciler.stop(pid)
  end

  test "server can be registered and addressed by name" do
    name = :"stream_reconciler_#{System.pid()}_#{System.unique_integer([:positive])}"
    {:ok, _pid} = StreamReconciler.start_link(key_fields: [:id], name: name)

    assert StreamReconciler.push_left(name, %{id: 1, v: 1}) == :ok
    assert StreamReconciler.push_right(name, %{id: 1, v: 2}) == :ok

    [entry] = StreamReconciler.take_matches(name)
    assert entry.differences == %{v: %{left: 1, right: 2}}

    StreamReconciler.stop(name)
  end

  # ---------------------------------------------------------------------------
  # Incremental matching
  # ---------------------------------------------------------------------------

  test "a match is produced as soon as both sides have pushed the key (left first)" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, name: "Alice"})
    assert StreamReconciler.take_matches(pid) == []
    assert StreamReconciler.pending_counts(pid) == %{left: 1, right: 0}

    StreamReconciler.push_right(pid, %{id: 1, name: "Alice"})

    [entry] = StreamReconciler.take_matches(pid)
    assert entry.key == %{id: 1}
    assert entry.left == %{id: 1, name: "Alice"}
    assert entry.right == %{id: 1, name: "Alice"}
    assert entry.differences == %{}
    assert StreamReconciler.pending_counts(pid) == %{left: 0, right: 0}

    StreamReconciler.stop(pid)
  end

  test "arrival order does not matter and :left/:right stay oriented by side" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_right(pid, %{id: 1, status: "right"})
    StreamReconciler.push_left(pid, %{id: 1, status: "left"})

    [entry] = StreamReconciler.take_matches(pid)
    assert entry.left == %{id: 1, status: "left"}
    assert entry.right == %{id: 1, status: "right"}
    assert entry.differences == %{status: %{left: "left", right: "right"}}

    StreamReconciler.stop(pid)
  end

  test "take_matches drains the queue in completion order and clears it" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    StreamReconciler.push_left(pid, %{id: 2})
    # id 2 completes first
    StreamReconciler.push_right(pid, %{id: 2})
    StreamReconciler.push_right(pid, %{id: 1})

    matches = StreamReconciler.take_matches(pid)
    assert Enum.map(matches, & &1.key) == [%{id: 2}, %{id: 1}]

    assert StreamReconciler.take_matches(pid) == []

    StreamReconciler.stop(pid)
  end

  test "pending_counts reports records still awaiting a partner" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    StreamReconciler.push_left(pid, %{id: 2})
    StreamReconciler.push_right(pid, %{id: 3})

    assert StreamReconciler.pending_counts(pid) == %{left: 2, right: 1}

    StreamReconciler.push_right(pid, %{id: 1})
    assert StreamReconciler.pending_counts(pid) == %{left: 1, right: 1}

    StreamReconciler.stop(pid)
  end

  # ---------------------------------------------------------------------------
  # Same-side duplicates: last write wins
  # ---------------------------------------------------------------------------

  test "pushing the same key twice on one side replaces the buffered record" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, v: "old"})
    StreamReconciler.push_left(pid, %{id: 1, v: "new"})

    assert StreamReconciler.pending_counts(pid) == %{left: 1, right: 0}

    StreamReconciler.push_right(pid, %{id: 1, v: "new"})

    [entry] = StreamReconciler.take_matches(pid)
    assert entry.left == %{id: 1, v: "new"}
    assert entry.differences == %{}

    StreamReconciler.stop(pid)
  end

  # ---------------------------------------------------------------------------
  # Diffing
  # ---------------------------------------------------------------------------

  test "compare_fields restricts which fields are diffed" do
    pid = start(key_fields: [:id], compare_fields: [:name])

    StreamReconciler.push_left(pid, %{id: 1, name: "Alice", note: "old"})
    StreamReconciler.push_right(pid, %{id: 1, name: "Alice", note: "new"})

    [entry] = StreamReconciler.take_matches(pid)
    assert entry.differences == %{}
    assert entry.left == %{id: 1, name: "Alice", note: "old"}
    assert entry.right == %{id: 1, name: "Alice", note: "new"}

    StreamReconciler.stop(pid)
  end

  test "without compare_fields all non-key fields are compared" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, a: 1, b: 2})
    StreamReconciler.push_right(pid, %{id: 1, a: 9, b: 2})

    [entry] = StreamReconciler.take_matches(pid)
    assert Map.has_key?(entry.differences, :a)
    refute Map.has_key?(entry.differences, :b)
    refute Map.has_key?(entry.differences, :id)

    StreamReconciler.stop(pid)
  end

  test "a compared field missing from one record is diffed as nil" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, score: 42})
    StreamReconciler.push_right(pid, %{id: 1})

    [entry] = StreamReconciler.take_matches(pid)
    assert entry.differences == %{score: %{left: 42, right: nil}}

    StreamReconciler.stop(pid)
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite keys only match when every key field agrees" do
    pid = start(key_fields: [:org_id, :user_id])

    StreamReconciler.push_left(pid, %{org_id: 1, user_id: 10, name: "Alice"})
    StreamReconciler.push_right(pid, %{org_id: 2, user_id: 10, name: "Carol"})

    assert StreamReconciler.take_matches(pid) == []
    assert StreamReconciler.pending_counts(pid) == %{left: 1, right: 1}

    StreamReconciler.push_right(pid, %{org_id: 1, user_id: 10, name: "Alice"})

    [entry] = StreamReconciler.take_matches(pid)
    assert entry.key == %{org_id: 1, user_id: 10}
    assert entry.differences == %{}

    StreamReconciler.stop(pid)
  end

  # ---------------------------------------------------------------------------
  # finalize/1
  # ---------------------------------------------------------------------------

  test "finalize returns uncollected matches plus buffered records and stops the server" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, v: 1})
    StreamReconciler.push_right(pid, %{id: 1, v: 2})
    StreamReconciler.push_left(pid, %{id: 2})
    StreamReconciler.push_right(pid, %{id: 3})

    ref = Process.monitor(pid)
    result = StreamReconciler.finalize(pid)

    assert [match] = result.matched
    assert match.key == %{id: 1}
    assert match.differences == %{v: %{left: 1, right: 2}}

    assert result.only_in_left == [%{id: 2}]
    assert result.only_in_right == [%{id: 3}]

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "finalize does not re-report matches already collected by take_matches" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    StreamReconciler.push_right(pid, %{id: 1})

    assert [_one] = StreamReconciler.take_matches(pid)

    result = StreamReconciler.finalize(pid)

    assert result.matched == []
    assert result.only_in_left == []
    assert result.only_in_right == []
  end

  test "finalize on an empty stream returns three empty lists" do
    pid = start(key_fields: [:id])

    assert StreamReconciler.finalize(pid) == %{
             matched: [],
             only_in_left: [],
             only_in_right: []
           }
  end

  # ---------------------------------------------------------------------------
  # Integration
  # ---------------------------------------------------------------------------

  test "interleaved stream: matches, diffs and leftovers" do
    pid = start(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, status: "active"})
    StreamReconciler.push_right(pid, %{id: 4, status: "active"})
    StreamReconciler.push_left(pid, %{id: 2, status: "active"})
    StreamReconciler.push_right(pid, %{id: 2, status: "inactive"})
    StreamReconciler.push_right(pid, %{id: 1, status: "active"})
    StreamReconciler.push_left(pid, %{id: 3, status: "inactive"})

    result = StreamReconciler.finalize(pid)

    assert length(result.matched) == 2
    assert Enum.map(result.matched, & &1.key) == [%{id: 2}, %{id: 1}]

    id2 = Enum.find(result.matched, &(&1.key == %{id: 2}))
    assert id2.differences == %{status: %{left: "active", right: "inactive"}}

    id1 = Enum.find(result.matched, &(&1.key == %{id: 1}))
    assert id1.differences == %{}

    assert result.only_in_left == [%{id: 3, status: "inactive"}]
    assert result.only_in_right == [%{id: 4, status: "active"}]
  end
end
