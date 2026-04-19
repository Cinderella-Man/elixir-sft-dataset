defmodule TwoPhaseSetTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = TwoPhaseSet.start_link([])
    %{s: pid}
  end

  # -------------------------------------------------------
  # Basic add / remove / member? / members
  # -------------------------------------------------------

  test "fresh set has no members", %{s: s} do
    assert TwoPhaseSet.members(s) == MapSet.new()
  end

  test "single add makes element a member", %{s: s} do
    assert :ok = TwoPhaseSet.add(s, :x)
    assert TwoPhaseSet.member?(s, :x) == true
    assert TwoPhaseSet.members(s) == MapSet.new([:x])
  end

  test "member? returns false for unknown element", %{s: s} do
    assert TwoPhaseSet.member?(s, :missing) == false
  end

  test "remove after add removes element", %{s: s} do
    TwoPhaseSet.add(s, :x)
    assert :ok = TwoPhaseSet.remove(s, :x)
    assert TwoPhaseSet.member?(s, :x) == false
    assert TwoPhaseSet.members(s) == MapSet.new()
  end

  test "adding an already-present element is a no-op", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.add(s, :x)
    assert TwoPhaseSet.members(s) == MapSet.new([:x])
  end

  # -------------------------------------------------------
  # 2P-Set constraint: no re-add after remove
  # -------------------------------------------------------

  test "re-adding a removed element raises ArgumentError", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    assert_raise ArgumentError, fn ->
      TwoPhaseSet.add(s, :x)
    end
  end

  test "removing an element that was never added raises ArgumentError", %{s: s} do
    assert_raise ArgumentError, fn ->
      TwoPhaseSet.remove(s, :never_added)
    end
  end

  test "removing an already-removed element raises ArgumentError", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    assert_raise ArgumentError, fn ->
      TwoPhaseSet.remove(s, :x)
    end
  end

  # -------------------------------------------------------
  # Multiple elements
  # -------------------------------------------------------

  test "multiple elements tracked independently", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)
    TwoPhaseSet.add(s, :c)
    TwoPhaseSet.remove(s, :b)

    assert TwoPhaseSet.members(s) == MapSet.new([:a, :c])
    assert TwoPhaseSet.member?(s, :a) == true
    assert TwoPhaseSet.member?(s, :b) == false
    assert TwoPhaseSet.member?(s, :c) == true
  end

  # -------------------------------------------------------
  # State structure
  # -------------------------------------------------------

  test "state returns the correct shape", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.add(s, :y)
    TwoPhaseSet.remove(s, :x)

    state = TwoPhaseSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :added)
    assert Map.has_key?(state, :removed)
    assert MapSet.member?(state.added, :x)
    assert MapSet.member?(state.added, :y)
    assert MapSet.member?(state.removed, :x)
    refute MapSet.member?(state.removed, :y)
  end

  test "state of a fresh set is empty MapSets", %{s: s} do
    state = TwoPhaseSet.state(s)
    assert state == %{added: MapSet.new(), removed: MapSet.new()}
  end

  test "tombstoned element remains in both added and removed sets", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    state = TwoPhaseSet.state(s)
    assert MapSet.member?(state.added, :x)
    assert MapSet.member?(state.removed, :x)
  end

  # -------------------------------------------------------
  # Merge basics
  # -------------------------------------------------------

  test "merging a remote state into an empty set", %{s: s} do
    remote = %{added: MapSet.new([:a, :b, :c]), removed: MapSet.new([:a])}
    assert :ok = TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.members(s) == MapSet.new([:b, :c])
  end

  test "merge unions the add-sets and remove-sets", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)

    remote = %{added: MapSet.new([:b, :c]), removed: MapSet.new([:a])}
    TwoPhaseSet.merge(s, remote)

    state = TwoPhaseSet.state(s)
    assert state.added == MapSet.new([:a, :b, :c])
    assert state.removed == MapSet.new([:a])
    assert TwoPhaseSet.members(s) == MapSet.new([:b, :c])
  end

  test "merge introduces tombstones from remote that override local adds", %{s: s} do
    TwoPhaseSet.add(s, :a)
    assert TwoPhaseSet.member?(s, :a) == true

    # Remote has removed :a
    remote = %{added: MapSet.new([:a]), removed: MapSet.new([:a])}
    TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.member?(s, :a) == false
  end

  test "merge does not shrink sets (grow-only)", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)
    TwoPhaseSet.add(s, :c)
    TwoPhaseSet.remove(s, :c)

    before_state = TwoPhaseSet.state(s)

    # Remote has fewer elements
    remote = %{added: MapSet.new([:a]), removed: MapSet.new()}
    TwoPhaseSet.merge(s, remote)

    after_state = TwoPhaseSet.state(s)

    # Sets only grow
    assert MapSet.subset?(before_state.added, after_state.added)
    assert MapSet.subset?(before_state.removed, after_state.removed)
  end

  # -------------------------------------------------------
  # Merge: CRDT properties
  # -------------------------------------------------------

  test "merge is idempotent", %{s: s} do
    TwoPhaseSet.add(s, :a)
    remote = %{added: MapSet.new([:a, :b]), removed: MapSet.new([:a])}

    TwoPhaseSet.merge(s, remote)
    members_after_first = TwoPhaseSet.members(s)
    state_after_first = TwoPhaseSet.state(s)

    TwoPhaseSet.merge(s, remote)
    members_after_second = TwoPhaseSet.members(s)
    state_after_second = TwoPhaseSet.state(s)

    assert members_after_first == members_after_second
    assert state_after_first == state_after_second
  end

  test "merge is commutative" do
    {:ok, s1} = TwoPhaseSet.start_link([])
    {:ok, s2} = TwoPhaseSet.start_link([])

    # Node 1 operations
    TwoPhaseSet.add(s1, :x)
    TwoPhaseSet.add(s1, :y)
    TwoPhaseSet.remove(s1, :x)

    # Node 2 operations
    TwoPhaseSet.add(s2, :y)
    TwoPhaseSet.add(s2, :z)

    state1 = TwoPhaseSet.state(s1)
    state2 = TwoPhaseSet.state(s2)

    # Merge state2 into s1
    TwoPhaseSet.merge(s1, state2)

    # Merge state1 into s2
    TwoPhaseSet.merge(s2, state1)

    # Both should converge
    assert TwoPhaseSet.members(s1) == TwoPhaseSet.members(s2)
    assert TwoPhaseSet.state(s1) == TwoPhaseSet.state(s2)
  end

  test "merge is associative" do
    {:ok, sa} = TwoPhaseSet.start_link([])
    {:ok, sb} = TwoPhaseSet.start_link([])
    {:ok, sc} = TwoPhaseSet.start_link([])

    TwoPhaseSet.add(sa, :a)
    TwoPhaseSet.add(sb, :b)
    TwoPhaseSet.add(sb, :a)
    TwoPhaseSet.remove(sb, :a)
    TwoPhaseSet.add(sc, :c)

    sta = TwoPhaseSet.state(sa)
    stb = TwoPhaseSet.state(sb)
    stc = TwoPhaseSet.state(sc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = TwoPhaseSet.start_link([])
    TwoPhaseSet.merge(p1, sta)
    TwoPhaseSet.merge(p1, stb)
    TwoPhaseSet.merge(p1, stc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = TwoPhaseSet.start_link([])
    {:ok, temp} = TwoPhaseSet.start_link([])
    TwoPhaseSet.merge(temp, stb)
    TwoPhaseSet.merge(temp, stc)
    bc_merged = TwoPhaseSet.state(temp)
    TwoPhaseSet.merge(p2, sta)
    TwoPhaseSet.merge(p2, bc_merged)

    assert TwoPhaseSet.members(p1) == TwoPhaseSet.members(p2)
    assert TwoPhaseSet.state(p1) == TwoPhaseSet.state(p2)
  end

  # -------------------------------------------------------
  # Simulated distributed scenario
  # -------------------------------------------------------

  test "two-node simulation with divergent ops then merge" do
    {:ok, node_a} = TwoPhaseSet.start_link([])
    {:ok, node_b} = TwoPhaseSet.start_link([])

    # Node A: adds users
    TwoPhaseSet.add(node_a, :alice)
    TwoPhaseSet.add(node_a, :bob)

    # Node B: adds alice too, then removes her
    TwoPhaseSet.add(node_b, :alice)
    TwoPhaseSet.add(node_b, :charlie)
    TwoPhaseSet.remove(node_b, :alice)

    # Before merge
    assert TwoPhaseSet.members(node_a) == MapSet.new([:alice, :bob])
    assert TwoPhaseSet.members(node_b) == MapSet.new([:charlie])

    # Bidirectional merge
    state_a = TwoPhaseSet.state(node_a)
    state_b = TwoPhaseSet.state(node_b)
    TwoPhaseSet.merge(node_a, state_b)
    TwoPhaseSet.merge(node_b, state_a)

    # Both converge: alice is tombstoned, bob and charlie remain
    assert TwoPhaseSet.members(node_a) == MapSet.new([:bob, :charlie])
    assert TwoPhaseSet.members(node_b) == MapSet.new([:bob, :charlie])
  end

  test "merge propagates tombstones — locally-added element disappears after merge", %{} do
    {:ok, n1} = TwoPhaseSet.start_link([])
    {:ok, n2} = TwoPhaseSet.start_link([])

    # Both add :x
    TwoPhaseSet.add(n1, :x)
    TwoPhaseSet.add(n2, :x)

    # n2 removes :x
    TwoPhaseSet.remove(n2, :x)

    # n1 still has :x
    assert TwoPhaseSet.member?(n1, :x) == true

    # After merge, n1 learns about the tombstone
    TwoPhaseSet.merge(n1, TwoPhaseSet.state(n2))
    assert TwoPhaseSet.member?(n1, :x) == false

    # And :x can never be re-added on n1
    assert_raise ArgumentError, fn ->
      TwoPhaseSet.add(n1, :x)
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "merging empty state into populated set is a no-op", %{s: s} do
    TwoPhaseSet.add(s, :a)
    before = TwoPhaseSet.state(s)
    TwoPhaseSet.merge(s, %{added: MapSet.new(), removed: MapSet.new()})
    assert TwoPhaseSet.state(s) == before
  end

  test "many elements", %{s: s} do
    for i <- 1..100 do
      TwoPhaseSet.add(s, :"elem_#{i}")
    end

    assert MapSet.size(TwoPhaseSet.members(s)) == 100
  end

  test "string elements work", %{s: s} do
    TwoPhaseSet.add(s, "hello")
    TwoPhaseSet.add(s, "world")
    assert TwoPhaseSet.member?(s, "hello") == true
    assert TwoPhaseSet.members(s) == MapSet.new(["hello", "world"])
  end

  test "named process registration works" do
    {:ok, _pid} = TwoPhaseSet.start_link(name: :my_2p_set)
    TwoPhaseSet.add(:my_2p_set, :x)
    assert TwoPhaseSet.member?(:my_2p_set, :x) == true
  end

  test "remove half the elements, verify membership", %{s: s} do
    elements = Enum.map(1..10, &:"e_#{&1}")
    Enum.each(elements, &TwoPhaseSet.add(s, &1))

    to_remove = Enum.take(elements, 5)
    Enum.each(to_remove, &TwoPhaseSet.remove(s, &1))

    remaining = Enum.drop(elements, 5) |> MapSet.new()
    assert TwoPhaseSet.members(s) == remaining
  end
end
