defmodule LWWSetTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = LWWSet.start_link([])
    %{s: pid}
  end

  # -------------------------------------------------------
  # Basic add / remove / member? / members
  # -------------------------------------------------------

  test "fresh set has no members", %{s: s} do
    assert LWWSet.members(s) == MapSet.new()
  end

  test "single add makes element a member", %{s: s} do
    assert :ok = LWWSet.add(s, :x, 1)
    assert LWWSet.member?(s, :x) == true
    assert LWWSet.members(s) == MapSet.new([:x])
  end

  test "member? returns false for unknown element", %{s: s} do
    assert LWWSet.member?(s, :missing) == false
  end

  test "remove after add with higher timestamp removes element", %{s: s} do
    LWWSet.add(s, :x, 1)
    assert :ok = LWWSet.remove(s, :x, 2)
    assert LWWSet.member?(s, :x) == false
    assert LWWSet.members(s) == MapSet.new()
  end

  test "remove before add (lower timestamp) does not prevent membership", %{s: s} do
    LWWSet.remove(s, :x, 1)
    LWWSet.add(s, :x, 5)
    assert LWWSet.member?(s, :x) == true
  end

  test "add with higher timestamp after remove re-adds element", %{s: s} do
    LWWSet.add(s, :x, 1)
    LWWSet.remove(s, :x, 2)
    LWWSet.add(s, :x, 3)
    assert LWWSet.member?(s, :x) == true
  end

  test "remove-wins on equal timestamps (tie-breaking)", %{s: s} do
    LWWSet.add(s, :x, 5)
    LWWSet.remove(s, :x, 5)
    assert LWWSet.member?(s, :x) == false
  end

  # -------------------------------------------------------
  # Timestamp max semantics
  # -------------------------------------------------------

  test "repeated adds keep the maximum timestamp", %{s: s} do
    LWWSet.add(s, :x, 10)
    LWWSet.add(s, :x, 3)
    state = LWWSet.state(s)
    assert state.adds[:x] == 10
  end

  test "repeated removes keep the maximum timestamp", %{s: s} do
    LWWSet.remove(s, :x, 10)
    LWWSet.remove(s, :x, 3)
    state = LWWSet.state(s)
    assert state.removes[:x] == 10
  end

  # -------------------------------------------------------
  # Multiple elements
  # -------------------------------------------------------

  test "multiple elements tracked independently", %{s: s} do
    LWWSet.add(s, :a, 1)
    LWWSet.add(s, :b, 2)
    LWWSet.add(s, :c, 3)
    LWWSet.remove(s, :b, 4)

    assert LWWSet.members(s) == MapSet.new([:a, :c])
    assert LWWSet.member?(s, :a) == true
    assert LWWSet.member?(s, :b) == false
    assert LWWSet.member?(s, :c) == true
  end

  test "elements are tracked independently in state", %{s: s} do
    LWWSet.add(s, :a, 5)
    LWWSet.add(s, :b, 10)
    LWWSet.remove(s, :a, 3)

    state = LWWSet.state(s)
    assert state.adds[:a] == 5
    assert state.adds[:b] == 10
    assert state.removes[:a] == 3
    assert state.removes[:b] == nil
  end

  # -------------------------------------------------------
  # State structure
  # -------------------------------------------------------

  test "state returns the correct shape", %{s: s} do
    LWWSet.add(s, :x, 4)
    LWWSet.remove(s, :x, 2)

    state = LWWSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :adds)
    assert Map.has_key?(state, :removes)
    assert state.adds[:x] == 4
    assert state.removes[:x] == 2
  end

  test "state of a fresh set is empty maps", %{s: s} do
    state = LWWSet.state(s)
    assert state == %{adds: %{}, removes: %{}}
  end

  # -------------------------------------------------------
  # Merge basics
  # -------------------------------------------------------

  test "merging a remote state into an empty set", %{s: s} do
    remote = %{adds: %{a: 5, b: 3}, removes: %{a: 1}}
    assert :ok = LWWSet.merge(s, remote)

    assert LWWSet.members(s) == MapSet.new([:a, :b])
    state = LWWSet.state(s)
    assert state.adds[:a] == 5
    assert state.adds[:b] == 3
    assert state.removes[:a] == 1
  end

  test "merge takes the max of each element's timestamps", %{s: s} do
    # Local: :a added at 3, removed at 1
    LWWSet.add(s, :a, 3)
    LWWSet.remove(s, :a, 1)

    # Remote: :a added at 5, no remove
    remote = %{adds: %{a: 5}, removes: %{}}
    LWWSet.merge(s, remote)

    state = LWWSet.state(s)
    # max(3, 5) = 5
    assert state.adds[:a] == 5
    # max(1, 0) = 1 (remote has no remove, treat as absent)
    assert state.removes[:a] == 1
    assert LWWSet.member?(s, :a) == true
  end

  test "merge does not lower existing timestamps", %{s: s} do
    LWWSet.add(s, :a, 10)
    LWWSet.remove(s, :a, 7)

    # Remote has lower values
    remote = %{adds: %{a: 2}, removes: %{a: 3}}
    LWWSet.merge(s, remote)

    state = LWWSet.state(s)
    assert state.adds[:a] == 10
    assert state.removes[:a] == 7
  end

  test "merge introduces new elements from remote", %{s: s} do
    LWWSet.add(s, :a, 1)
    remote = %{adds: %{b: 5, c: 3}, removes: %{c: 2}}
    LWWSet.merge(s, remote)

    assert LWWSet.members(s) == MapSet.new([:a, :b, :c])
  end

  test "merge where remote remove overrides local add", %{s: s} do
    LWWSet.add(s, :a, 5)
    remote = %{adds: %{}, removes: %{a: 10}}
    LWWSet.merge(s, remote)

    assert LWWSet.member?(s, :a) == false
  end

  # -------------------------------------------------------
  # Merge: CRDT properties
  # -------------------------------------------------------

  test "merge is idempotent", %{s: s} do
    LWWSet.add(s, :a, 3)
    remote = %{adds: %{a: 5, b: 2}, removes: %{a: 1}}

    LWWSet.merge(s, remote)
    members_after_first = LWWSet.members(s)
    state_after_first = LWWSet.state(s)

    LWWSet.merge(s, remote)
    members_after_second = LWWSet.members(s)
    state_after_second = LWWSet.state(s)

    assert members_after_first == members_after_second
    assert state_after_first == state_after_second
  end

  test "merge is commutative" do
    {:ok, s1} = LWWSet.start_link([])
    {:ok, s2} = LWWSet.start_link([])

    # Node 1 operations
    LWWSet.add(s1, :x, 5)
    LWWSet.remove(s1, :x, 2)
    LWWSet.add(s1, :y, 1)

    # Node 2 operations
    LWWSet.add(s2, :y, 8)
    LWWSet.remove(s2, :y, 3)
    LWWSet.add(s2, :x, 2)

    state1 = LWWSet.state(s1)
    state2 = LWWSet.state(s2)

    # Merge state2 into s1
    LWWSet.merge(s1, state2)

    # Merge state1 into s2
    LWWSet.merge(s2, state1)

    # Both should converge to the same members and state
    assert LWWSet.members(s1) == LWWSet.members(s2)
    assert LWWSet.state(s1) == LWWSet.state(s2)
  end

  test "merge is associative" do
    {:ok, sa} = LWWSet.start_link([])
    {:ok, sb} = LWWSet.start_link([])
    {:ok, sc} = LWWSet.start_link([])

    LWWSet.add(sa, :a, 3)
    LWWSet.add(sb, :b, 5)
    LWWSet.remove(sb, :a, 2)
    LWWSet.add(sc, :c, 7)
    LWWSet.remove(sc, :b, 1)

    sta = LWWSet.state(sa)
    stb = LWWSet.state(sb)
    stc = LWWSet.state(sc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = LWWSet.start_link([])
    LWWSet.merge(p1, sta)
    LWWSet.merge(p1, stb)
    LWWSet.merge(p1, stc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = LWWSet.start_link([])
    {:ok, temp} = LWWSet.start_link([])
    LWWSet.merge(temp, stb)
    LWWSet.merge(temp, stc)
    bc_merged = LWWSet.state(temp)
    LWWSet.merge(p2, sta)
    LWWSet.merge(p2, bc_merged)

    assert LWWSet.members(p1) == LWWSet.members(p2)
    assert LWWSet.state(p1) == LWWSet.state(p2)
  end

  # -------------------------------------------------------
  # Simulated distributed scenario
  # -------------------------------------------------------

  test "two-node simulation with divergent ops then merge" do
    {:ok, node_a} = LWWSet.start_link([])
    {:ok, node_b} = LWWSet.start_link([])

    # Node A: adds :user1 and :user2
    LWWSet.add(node_a, :user1, 1)
    LWWSet.add(node_a, :user2, 2)

    # Node B: adds :user3, removes :user1 (seen via earlier sync)
    LWWSet.add(node_b, :user3, 3)
    LWWSet.add(node_b, :user1, 1)
    LWWSet.remove(node_b, :user1, 4)

    # Before merge, each node only sees its own ops
    assert LWWSet.members(node_a) == MapSet.new([:user1, :user2])
    assert LWWSet.members(node_b) == MapSet.new([:user3])

    # Bidirectional merge (simulating gossip)
    state_a = LWWSet.state(node_a)
    state_b = LWWSet.state(node_b)
    LWWSet.merge(node_a, state_b)
    LWWSet.merge(node_b, state_a)

    # Both converge: user1 removed (remove at 4 > add at 1), user2 and user3 present
    assert LWWSet.members(node_a) == MapSet.new([:user2, :user3])
    assert LWWSet.members(node_b) == MapSet.new([:user2, :user3])
  end

  test "repeated merges after continued operations converge" do
    {:ok, n1} = LWWSet.start_link([])
    {:ok, n2} = LWWSet.start_link([])

    # Round 1
    LWWSet.add(n1, :a, 1)
    LWWSet.add(n2, :b, 2)

    s1 = LWWSet.state(n1)
    s2 = LWWSet.state(n2)
    LWWSet.merge(n1, s2)
    LWWSet.merge(n2, s1)
    assert LWWSet.members(n1) == MapSet.new([:a, :b])
    assert LWWSet.members(n2) == MapSet.new([:a, :b])

    # Round 2: more operations after merge
    LWWSet.add(n1, :c, 3)
    LWWSet.remove(n2, :a, 4)

    s1 = LWWSet.state(n1)
    s2 = LWWSet.state(n2)
    LWWSet.merge(n1, s2)
    LWWSet.merge(n2, s1)

    # :a removed at 4 > added at 1, :b present, :c present
    assert LWWSet.members(n1) == MapSet.new([:b, :c])
    assert LWWSet.members(n2) == MapSet.new([:b, :c])
  end

  # -------------------------------------------------------
  # Argument validation
  # -------------------------------------------------------

  test "add with non-positive timestamp raises", %{s: s} do
    assert_raise ArgumentError, fn ->
      LWWSet.add(s, :x, 0)
    end

    assert_raise ArgumentError, fn ->
      LWWSet.add(s, :x, -1)
    end
  end

  test "remove with non-positive timestamp raises", %{s: s} do
    assert_raise ArgumentError, fn ->
      LWWSet.remove(s, :x, 0)
    end

    assert_raise ArgumentError, fn ->
      LWWSet.remove(s, :x, -5)
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "merging empty state into populated set is a no-op", %{s: s} do
    LWWSet.add(s, :a, 5)
    before = LWWSet.state(s)
    LWWSet.merge(s, %{adds: %{}, removes: %{}})
    assert LWWSet.state(s) == before
  end

  test "many elements with small timestamps", %{s: s} do
    for i <- 1..100 do
      LWWSet.add(s, :"elem_#{i}", 1)
    end

    assert MapSet.size(LWWSet.members(s)) == 100
  end

  test "large timestamps work correctly", %{s: s} do
    LWWSet.add(s, :a, 1_000_000)
    LWWSet.remove(s, :a, 999_999)
    assert LWWSet.member?(s, :a) == true
  end

  test "remove without prior add keeps element absent", %{s: s} do
    LWWSet.remove(s, :ghost, 10)
    assert LWWSet.member?(s, :ghost) == false
    state = LWWSet.state(s)
    assert state.removes[:ghost] == 10
    assert state.adds[:ghost] == nil
  end

  test "string elements work", %{s: s} do
    LWWSet.add(s, "hello", 1)
    LWWSet.add(s, "world", 2)
    assert LWWSet.member?(s, "hello") == true
    assert LWWSet.members(s) == MapSet.new(["hello", "world"])
  end

  test "named process registration works" do
    {:ok, _pid} = LWWSet.start_link(name: :my_lww_set)
    LWWSet.add(:my_lww_set, :x, 1)
    assert LWWSet.member?(:my_lww_set, :x) == true
  end
end
