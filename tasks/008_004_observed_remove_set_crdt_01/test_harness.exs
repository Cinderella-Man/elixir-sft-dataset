defmodule ORSetTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = ORSet.start_link([])
    %{s: pid}
  end

  # -------------------------------------------------------
  # Basic add / remove / member? / members
  # -------------------------------------------------------

  test "fresh set has no members", %{s: s} do
    assert ORSet.members(s) == MapSet.new()
  end

  test "single add makes element a member", %{s: s} do
    assert :ok = ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
    assert ORSet.members(s) == MapSet.new([:x])
  end

  test "member? returns false for unknown element", %{s: s} do
    assert ORSet.member?(s, :missing) == false
  end

  test "remove after add removes element", %{s: s} do
    ORSet.add(s, :x, :node_a)
    assert :ok = ORSet.remove(s, :x)
    assert ORSet.member?(s, :x) == false
    assert ORSet.members(s) == MapSet.new()
  end

  test "removing non-member raises ArgumentError", %{s: s} do
    assert_raise ArgumentError, fn ->
      ORSet.remove(s, :never_added)
    end
  end

  # -------------------------------------------------------
  # OR-Set key property: re-add after remove
  # -------------------------------------------------------

  test "element can be re-added after removal", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.remove(s, :x)
    assert ORSet.member?(s, :x) == false

    ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
  end

  test "multiple add-remove cycles work", %{s: s} do
    for _i <- 1..5 do
      ORSet.add(s, :x, :node_a)
      assert ORSet.member?(s, :x) == true
      ORSet.remove(s, :x)
      assert ORSet.member?(s, :x) == false
    end

    ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
  end

  # -------------------------------------------------------
  # Unique tags
  # -------------------------------------------------------

  test "each add generates a unique tag", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :x, :node_a)

    state = ORSet.state(s)
    tags = state.entries[:x]
    # Two adds from same node => two distinct tags
    assert MapSet.size(tags) == 2
  end

  test "tags from different nodes are distinct", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :x, :node_b)

    state = ORSet.state(s)
    tags = state.entries[:x]
    assert MapSet.size(tags) == 2
  end

  test "clock increments per node", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :y, :node_a)
    ORSet.add(s, :z, :node_b)

    state = ORSet.state(s)
    assert state.clock[:node_a] == 2
    assert state.clock[:node_b] == 1
  end

  # -------------------------------------------------------
  # Multiple elements
  # -------------------------------------------------------

  test "multiple elements tracked independently", %{s: s} do
    ORSet.add(s, :a, :n1)
    ORSet.add(s, :b, :n1)
    ORSet.add(s, :c, :n1)
    ORSet.remove(s, :b)

    assert ORSet.members(s) == MapSet.new([:a, :c])
  end

  # -------------------------------------------------------
  # State structure
  # -------------------------------------------------------

  test "state returns the correct shape", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :y, :node_b)
    ORSet.remove(s, :x)

    state = ORSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :entries)
    assert Map.has_key?(state, :tombstones)
    assert Map.has_key?(state, :clock)

    # :x was removed, so its entry should be gone
    refute Map.has_key?(state.entries, :x)
    # :y should still have tags
    assert MapSet.size(state.entries[:y]) == 1
    # tombstones should have the tag from :x
    assert MapSet.size(state.tombstones) == 1
  end

  test "state of a fresh set is empty", %{s: s} do
    state = ORSet.state(s)
    assert state.entries == %{}
    assert state.tombstones == MapSet.new()
    assert state.clock == %{}
  end

  # -------------------------------------------------------
  # Merge basics
  # -------------------------------------------------------

  test "merging a remote state into an empty set", %{s: s} do
    # Build a remote state manually
    remote = %{
      entries: %{a: MapSet.new([{:r, 1}]), b: MapSet.new([{:r, 2}])},
      tombstones: MapSet.new(),
      clock: %{r: 2}
    }

    assert :ok = ORSet.merge(s, remote)
    assert ORSet.members(s) == MapSet.new([:a, :b])
  end

  test "merge unions tags and tombstones", %{s: s} do
    ORSet.add(s, :x, :local)

    remote = %{
      entries: %{x: MapSet.new([{:remote, 1}])},
      tombstones: MapSet.new(),
      clock: %{remote: 1}
    }

    ORSet.merge(s, remote)

    state = ORSet.state(s)
    # Should have both tags for :x
    assert MapSet.size(state.entries[:x]) == 2
  end

  test "merge applies remote tombstones to local entries", %{s: s} do
    ORSet.add(s, :x, :local)
    local_state = ORSet.state(s)
    local_tag = local_state.entries[:x] |> MapSet.to_list() |> hd()

    # Remote has tombstoned that exact tag
    remote = %{
      entries: %{},
      tombstones: MapSet.new([local_tag]),
      clock: %{}
    }

    ORSet.merge(s, remote)
    assert ORSet.member?(s, :x) == false
  end

  test "merge does not remove entries with tags not in tombstones", %{s: s} do
    ORSet.add(s, :x, :local)

    # Remote tombstones a different tag
    remote = %{
      entries: %{},
      tombstones: MapSet.new([{:other_node, 999}]),
      clock: %{}
    }

    ORSet.merge(s, remote)
    assert ORSet.member?(s, :x) == true
  end

  # -------------------------------------------------------
  # Add-wins semantics (the key OR-Set property)
  # -------------------------------------------------------

  test "concurrent add and remove: add wins" do
    {:ok, node_a} = ORSet.start_link([])
    {:ok, node_b} = ORSet.start_link([])

    # Both start with :x
    ORSet.add(node_a, :x, :a)
    state_a = ORSet.state(node_a)
    ORSet.merge(node_b, state_a)

    # Now both have :x with tag {:a, 1}
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == true

    # CONCURRENT: node_a re-adds :x (new tag {:a, 2}), node_b removes :x
    ORSet.add(node_a, :x, :a)
    ORSet.remove(node_b, :x)

    # node_a: :x has tags [{:a, 1}, {:a, 2}]
    # node_b: :x removed (tombstones: [{:a, 1}])
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == false

    # Bidirectional merge
    sa = ORSet.state(node_a)
    sb = ORSet.state(node_b)
    ORSet.merge(node_a, sb)
    ORSet.merge(node_b, sa)

    # ADD WINS: :x is present because {:a, 2} is NOT in node_b's tombstones
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == true
  end

  # -------------------------------------------------------
  # Merge: CRDT properties
  # -------------------------------------------------------

  test "merge is idempotent", %{s: s} do
    ORSet.add(s, :a, :n1)
    remote = %{
      entries: %{b: MapSet.new([{:n2, 1}])},
      tombstones: MapSet.new(),
      clock: %{n2: 1}
    }

    ORSet.merge(s, remote)
    members_first = ORSet.members(s)
    state_first = ORSet.state(s)

    ORSet.merge(s, remote)
    members_second = ORSet.members(s)
    state_second = ORSet.state(s)

    assert members_first == members_second
    assert state_first == state_second
  end

  test "merge is commutative" do
    {:ok, s1} = ORSet.start_link([])
    {:ok, s2} = ORSet.start_link([])

    ORSet.add(s1, :x, :n1)
    ORSet.add(s1, :y, :n1)

    ORSet.add(s2, :y, :n2)
    ORSet.add(s2, :z, :n2)
    ORSet.remove(s2, :y)

    state1 = ORSet.state(s1)
    state2 = ORSet.state(s2)

    # Merge in both directions
    ORSet.merge(s1, state2)
    ORSet.merge(s2, state1)

    assert ORSet.members(s1) == ORSet.members(s2)
    assert ORSet.state(s1) == ORSet.state(s2)
  end

  test "merge is associative" do
    {:ok, sa} = ORSet.start_link([])
    {:ok, sb} = ORSet.start_link([])
    {:ok, sc} = ORSet.start_link([])

    ORSet.add(sa, :a, :n1)
    ORSet.add(sb, :b, :n2)
    ORSet.add(sc, :c, :n3)
    ORSet.add(sc, :a, :n3)

    sta = ORSet.state(sa)
    stb = ORSet.state(sb)
    stc = ORSet.state(sc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = ORSet.start_link([])
    ORSet.merge(p1, sta)
    ORSet.merge(p1, stb)
    ORSet.merge(p1, stc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = ORSet.start_link([])
    {:ok, temp} = ORSet.start_link([])
    ORSet.merge(temp, stb)
    ORSet.merge(temp, stc)
    bc_merged = ORSet.state(temp)
    ORSet.merge(p2, sta)
    ORSet.merge(p2, bc_merged)

    assert ORSet.members(p1) == ORSet.members(p2)
    assert ORSet.state(p1) == ORSet.state(p2)
  end

  # -------------------------------------------------------
  # Simulated distributed scenario
  # -------------------------------------------------------

  test "two-node simulation with divergent ops then merge" do
    {:ok, node_a} = ORSet.start_link([])
    {:ok, node_b} = ORSet.start_link([])

    # Node A adds users
    ORSet.add(node_a, :alice, :a)
    ORSet.add(node_a, :bob, :a)

    # Node B adds users
    ORSet.add(node_b, :charlie, :b)
    ORSet.add(node_b, :bob, :b)

    # Before merge
    assert ORSet.members(node_a) == MapSet.new([:alice, :bob])
    assert ORSet.members(node_b) == MapSet.new([:charlie, :bob])

    # Bidirectional merge
    sa = ORSet.state(node_a)
    sb = ORSet.state(node_b)
    ORSet.merge(node_a, sb)
    ORSet.merge(node_b, sa)

    # Both converge to all users
    assert ORSet.members(node_a) == MapSet.new([:alice, :bob, :charlie])
    assert ORSet.members(node_b) == MapSet.new([:alice, :bob, :charlie])
  end

  test "repeated merges after continued operations converge" do
    {:ok, n1} = ORSet.start_link([])
    {:ok, n2} = ORSet.start_link([])

    # Round 1
    ORSet.add(n1, :a, :n1)
    ORSet.add(n2, :b, :n2)

    s1 = ORSet.state(n1)
    s2 = ORSet.state(n2)
    ORSet.merge(n1, s2)
    ORSet.merge(n2, s1)
    assert ORSet.members(n1) == MapSet.new([:a, :b])
    assert ORSet.members(n2) == MapSet.new([:a, :b])

    # Round 2: n1 adds :c, n2 removes :a
    ORSet.add(n1, :c, :n1)
    ORSet.remove(n2, :a)

    s1 = ORSet.state(n1)
    s2 = ORSet.state(n2)
    ORSet.merge(n1, s2)
    ORSet.merge(n2, s1)

    # :a removed, :b and :c remain
    assert ORSet.members(n1) == MapSet.new([:b, :c])
    assert ORSet.members(n2) == MapSet.new([:b, :c])
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "merging empty state into populated set is a no-op", %{s: s} do
    ORSet.add(s, :a, :n1)
    before = ORSet.state(s)
    ORSet.merge(s, %{entries: %{}, tombstones: MapSet.new(), clock: %{}})
    assert ORSet.state(s) == before
  end

  test "many elements", %{s: s} do
    for i <- 1..100 do
      ORSet.add(s, :"elem_#{i}", :node)
    end

    assert MapSet.size(ORSet.members(s)) == 100
  end

  test "string elements work", %{s: s} do
    ORSet.add(s, "hello", :n1)
    ORSet.add(s, "world", :n1)
    assert ORSet.member?(s, "hello") == true
    assert ORSet.members(s) == MapSet.new(["hello", "world"])
  end

  test "named process registration works" do
    {:ok, _pid} = ORSet.start_link(name: :my_or_set)
    ORSet.add(:my_or_set, :x, :n1)
    assert ORSet.member?(:my_or_set, :x) == true
  end

  test "removing then re-adding from same node works", %{s: s} do
    ORSet.add(s, :x, :n1)
    ORSet.remove(s, :x)
    ORSet.add(s, :x, :n1)

    state = ORSet.state(s)
    # Old tag is in tombstones, new tag is in entries
    assert MapSet.size(state.tombstones) == 1
    assert MapSet.size(state.entries[:x]) == 1

    # The live tag should NOT be in tombstones
    live_tag = state.entries[:x] |> MapSet.to_list() |> hd()
    refute MapSet.member?(state.tombstones, live_tag)
  end
end
