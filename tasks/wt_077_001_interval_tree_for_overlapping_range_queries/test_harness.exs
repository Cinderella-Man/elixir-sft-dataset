defmodule IntervalTreeTest do
  use ExUnit.Case, async: true

  # Sizes used by the complexity tests below. `@big` is 32x `@small`, so a tree
  # that stays balanced answers a query / absorbs an insert in ~1.7x the work,
  # while a tree that degenerates into a list needs ~32x the work.
  @small 100
  @big 3200

  # -------------------------------------------------------
  # Empty tree
  # -------------------------------------------------------

  test "overlapping on empty tree returns empty list" do
    tree = IntervalTree.new()
    assert [] = IntervalTree.overlapping(tree, {1, 10})
  end

  test "enclosing on empty tree returns empty list" do
    tree = IntervalTree.new()
    assert [] = IntervalTree.enclosing(tree, 5)
  end

  # -------------------------------------------------------
  # Single interval
  # -------------------------------------------------------

  test "single interval is found by overlapping query that contains it" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [{3, 7}] = IntervalTree.overlapping(tree, {1, 10})
  end

  test "single interval does not match a non-overlapping query" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [] = IntervalTree.overlapping(tree, {10, 20})
  end

  test "enclosing finds interval containing the point" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [{3, 7}] = IntervalTree.enclosing(tree, 5)
  end

  test "enclosing misses interval that does not contain the point" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [] = IntervalTree.enclosing(tree, 8)
  end

  # -------------------------------------------------------
  # Touching intervals (end of one == start of another)
  # -------------------------------------------------------

  test "touching intervals are considered overlapping" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 5})
      |> IntervalTree.insert({5, 10})

    result = IntervalTree.overlapping(tree, {5, 5})
    assert length(result) == 2
    assert {1, 5} in result
    assert {5, 10} in result
  end

  test "query touching the end of an interval still matches" do
    tree = IntervalTree.new() |> IntervalTree.insert({1, 5})
    assert [{1, 5}] = IntervalTree.overlapping(tree, {5, 8})
  end

  test "query touching the start of an interval still matches" do
    tree = IntervalTree.new() |> IntervalTree.insert({5, 10})
    assert [{5, 10}] = IntervalTree.overlapping(tree, {2, 5})
  end

  # -------------------------------------------------------
  # Degenerate (point) intervals — start == end
  # -------------------------------------------------------

  test "degenerate interval is found when query covers its point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [{4, 4}] = IntervalTree.overlapping(tree, {1, 10})
  end

  test "degenerate interval is found by enclosing at its exact point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [{4, 4}] = IntervalTree.enclosing(tree, 4)
  end

  test "degenerate interval is missed when query does not cover its point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [] = IntervalTree.overlapping(tree, {5, 10})
  end

  test "degenerate query range matches intervals that touch that point" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 3})
      |> IntervalTree.insert({3, 6})
      |> IntervalTree.insert({4, 8})

    result = IntervalTree.overlapping(tree, {3, 3})
    assert length(result) == 2
    assert {1, 3} in result
    assert {3, 6} in result
  end

  # -------------------------------------------------------
  # Multiple intervals — correct subset returned
  # -------------------------------------------------------

  test "only overlapping intervals are returned, not all" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 2})
      |> IntervalTree.insert({5, 8})
      |> IntervalTree.insert({10, 15})
      |> IntervalTree.insert({20, 25})

    result = IntervalTree.overlapping(tree, {6, 12})
    assert length(result) == 2
    assert {5, 8} in result
    assert {10, 15} in result
  end

  test "enclosing returns all intervals that contain the point" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 10})
      |> IntervalTree.insert({3, 7})
      |> IntervalTree.insert({6, 15})
      |> IntervalTree.insert({20, 30})

    result = IntervalTree.enclosing(tree, 6)
    assert length(result) == 3
    assert {1, 10} in result
    assert {3, 7} in result
    assert {6, 15} in result
    refute {20, 30} in result
  end

  # -------------------------------------------------------
  # Persistence — insert returns new tree, original unchanged
  # -------------------------------------------------------

  test "insert is non-destructive — original tree is unchanged" do
    t0 = IntervalTree.new()
    t1 = IntervalTree.insert(t0, {1, 5})
    t2 = IntervalTree.insert(t1, {10, 20})

    assert [] = IntervalTree.overlapping(t0, {1, 100})
    assert [{1, 5}] = IntervalTree.overlapping(t1, {1, 100})

    result = IntervalTree.overlapping(t2, {1, 100})
    assert length(result) == 2
    assert {1, 5} in result
    assert {10, 20} in result
  end

  # -------------------------------------------------------
  # Duplicate intervals
  # -------------------------------------------------------

  test "inserting the same interval twice returns it twice" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({2, 8})
      |> IntervalTree.insert({2, 8})

    result = IntervalTree.overlapping(tree, {1, 10})
    assert length(result) == 2
  end

  # -------------------------------------------------------
  # Large insertion — correctness at scale
  # -------------------------------------------------------

  test "correct results with many intervals inserted" do
    # Insert 200 non-overlapping intervals: {0,9}, {10,19}, ..., {1990,1999}
    tree =
      Enum.reduce(0..199, IntervalTree.new(), fn i, acc ->
        IntervalTree.insert(acc, {i * 10, i * 10 + 9})
      end)

    # Query that touches exactly three intervals
    result = IntervalTree.overlapping(tree, {95, 115})
    assert length(result) == 3
    assert {90, 99} in result
    assert {100, 109} in result
    assert {110, 119} in result

    # Point query
    result2 = IntervalTree.enclosing(tree, 155)
    assert [{150, 159}] = result2
  end

  # -------------------------------------------------------
  # Equal-start intervals at the exact query boundary
  # -------------------------------------------------------
  # After rebalancing, an interval whose start equals another node's start can
  # end up in that node's right subtree. When the query finish (or the queried
  # point) equals that shared start, every stored copy still touches the query
  # ("touching counts"), so none may be skipped.

  test "overlapping query ending exactly at duplicated starts returns every stored copy" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 8})
      |> IntervalTree.insert({6, 7})
      |> IntervalTree.insert({4, 4})
      |> IntervalTree.insert({10, 10})
      |> IntervalTree.insert({10, 10})

    # {10, 10} is stored twice; both share point 10 with each query below.
    assert Enum.sort(IntervalTree.overlapping(tree, {10, 10})) == [{10, 10}, {10, 10}]
    assert Enum.sort(IntervalTree.overlapping(tree, {9, 10})) == [{10, 10}, {10, 10}]

    assert Enum.sort(IntervalTree.overlapping(tree, {0, 10})) ==
             [{1, 8}, {4, 4}, {6, 7}, {10, 10}, {10, 10}]
  end

  test "enclosing at a point equal to duplicated starts returns every stored copy" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 8})
      |> IntervalTree.insert({6, 7})
      |> IntervalTree.insert({4, 4})
      |> IntervalTree.insert({10, 10})
      |> IntervalTree.insert({10, 10})

    # Both copies of {10, 10} contain 10 (s <= point <= f), so both must appear.
    assert Enum.sort(IntervalTree.enclosing(tree, 10)) == [{10, 10}, {10, 10}]
  end

  test "older tree values stay unchanged after many derived inserts" do
    t0 = IntervalTree.new()
    t1 = t0 |> IntervalTree.insert({1, 5}) |> IntervalTree.insert({10, 20})
    before = Enum.sort(IntervalTree.overlapping(t1, {0, 100}))
    assert before == [{1, 5}, {10, 20}]

    _t2 =
      Enum.reduce(1..60, t1, fn i, acc ->
        IntervalTree.insert(acc, {i, i + 3})
      end)

    assert Enum.sort(IntervalTree.overlapping(t1, {0, 100})) == before
    assert Enum.sort(IntervalTree.enclosing(t1, 12)) == [{10, 20}]
    assert IntervalTree.overlapping(t0, {0, 100}) == []
    assert IntervalTree.enclosing(t0, 12) == []
  end

  test "ascending, descending and arbitrary insertion orders answer queries identically" do
    ivs = Enum.map(0..49, fn i -> {i * 3, i * 3 + 5} end)
    arbitrary = Enum.sort_by(ivs, fn {s, _f} -> rem(s * 7, 31) end)

    build = fn list ->
      Enum.reduce(list, IntervalTree.new(), fn iv, acc -> IntervalTree.insert(acc, iv) end)
    end

    asc = build.(ivs)
    desc = build.(Enum.reverse(ivs))
    arb = build.(arbitrary)

    for {qs, qf} = q <- [{0, 4}, {7, 9}, {100, 110}, {200, 200}, {-5, -1}] do
      expected = Enum.sort(Enum.filter(ivs, fn {s, f} -> s <= qf and f >= qs end))
      assert Enum.sort(IntervalTree.overlapping(asc, q)) == expected
      assert Enum.sort(IntervalTree.overlapping(desc, q)) == expected
      assert Enum.sort(IntervalTree.overlapping(arb, q)) == expected
    end

    for p <- [0, 5, 6, 150, 152, 500] do
      expected = Enum.sort(Enum.filter(ivs, fn {s, f} -> s <= p and p <= f end))
      assert Enum.sort(IntervalTree.enclosing(asc, p)) == expected
      assert Enum.sort(IntervalTree.enclosing(desc, p)) == expected
      assert Enum.sort(IntervalTree.enclosing(arb, p)) == expected
    end
  end

  test "degenerate query range agrees with enclosing at every probed point" do
    tree =
      Enum.reduce([{1, 5}, {3, 3}, {3, 9}, {5, 5}, {6, 12}, {20, 30}], IntervalTree.new(), fn iv,
                                                                                              acc ->
        IntervalTree.insert(acc, iv)
      end)

    for p <- [0, 1, 3, 5, 6, 9, 12, 13, 20, 30, 31] do
      assert Enum.sort(IntervalTree.overlapping(tree, {p, p})) ==
               Enum.sort(IntervalTree.enclosing(tree, p))
    end

    assert Enum.sort(IntervalTree.overlapping(tree, {3, 3})) == [{1, 5}, {3, 3}, {3, 9}]
  end

  test "enclosing includes an interval at both endpoints but not just past the finish" do
    tree = IntervalTree.new() |> IntervalTree.insert({1, 5})

    assert IntervalTree.enclosing(tree, 1) == [{1, 5}]
    assert IntervalTree.enclosing(tree, 5) == [{1, 5}]
    assert IntervalTree.enclosing(tree, 6) == []
    assert IntervalTree.enclosing(tree, 0) == []
  end

  test "several intervals sharing one start are all retained and queryable" do
    tree =
      Enum.reduce([{4, 4}, {4, 6}, {4, 100}, {4, 6}, {1, 2}], IntervalTree.new(), fn iv, acc ->
        IntervalTree.insert(acc, iv)
      end)

    assert Enum.sort(IntervalTree.enclosing(tree, 4)) == [{4, 4}, {4, 6}, {4, 6}, {4, 100}]
    assert Enum.sort(IntervalTree.overlapping(tree, {5, 5})) == [{4, 6}, {4, 6}, {4, 100}]
    assert IntervalTree.enclosing(tree, 50) == [{4, 100}]

    assert Enum.sort(IntervalTree.overlapping(tree, {0, 4})) ==
             [{1, 2}, {4, 4}, {4, 6}, {4, 6}, {4, 100}]
  end

  test "repeated identical queries on one tree value return the same multiset" do
    tree =
      Enum.reduce([{2, 8}, {2, 8}, {5, 5}, {9, 11}], IntervalTree.new(), fn iv, acc ->
        IntervalTree.insert(acc, iv)
      end)

    first = Enum.sort(IntervalTree.overlapping(tree, {4, 6}))
    _ = IntervalTree.enclosing(tree, 5)
    _ = IntervalTree.overlapping(tree, {0, 100})
    second = Enum.sort(IntervalTree.overlapping(tree, {4, 6}))

    assert first == [{2, 8}, {2, 8}, {5, 5}]
    assert second == first
    assert Enum.sort(IntervalTree.enclosing(tree, 5)) == [{2, 8}, {2, 8}, {5, 5}]
    assert Enum.sort(IntervalTree.enclosing(tree, 5)) == [{2, 8}, {2, 8}, {5, 5}]
  end

  # -------------------------------------------------------
  # Rebalancing, exercised through the public API
  # -------------------------------------------------------
  # `insert/2` must keep the tree balanced whatever order intervals arrive in,
  # which means every one of the four AVL fix-up shapes (Left-Left, Left-Right,
  # Right-Right, Right-Left) has to be reachable and has to leave a tree whose
  # queries still return the exact stored multiset. These tests drive each shape
  # with the smallest sequence that triggers it, then probe every endpoint.

  test "each of the four rebalancing shapes keeps every interval queryable" do
    cases = [
      {"left-left", [{30, 31}, {20, 21}, {10, 11}]},
      {"left-right", [{30, 31}, {10, 11}, {20, 21}]},
      {"right-right", [{10, 11}, {20, 21}, {30, 31}]},
      {"right-left", [{10, 11}, {30, 31}, {20, 21}]}
    ]

    for {label, ivs} <- cases do
      tree = build(ivs)

      assert Enum.sort(IntervalTree.overlapping(tree, {0, 40})) == Enum.sort(ivs), label
      assert IntervalTree.overlapping(tree, {40, 50}) == [], label
      assert IntervalTree.overlapping(tree, {0, 9}) == [], label

      for {s, f} <- ivs do
        assert IntervalTree.enclosing(tree, s) == [{s, f}], label
        assert IntervalTree.enclosing(tree, f) == [{s, f}], label
        assert IntervalTree.enclosing(tree, s - 1) == [], label
        assert IntervalTree.enclosing(tree, f + 1) == [], label
        assert IntervalTree.overlapping(tree, {s, f}) == [{s, f}], label
      end
    end
  end

  test "every insertion permutation of a small set answers queries identically" do
    ivs = [{1, 10}, {2, 3}, {5, 20}, {5, 5}, {12, 14}, {30, 31}]
    probes = [0, 1, 2, 4, 5, 10, 11, 13, 20, 21, 30, 32]

    for order <- permutations(ivs) do
      tree = build(order)

      assert Enum.sort(IntervalTree.overlapping(tree, {0, 100})) == Enum.sort(ivs)

      for p <- probes do
        expected = ivs |> Enum.filter(fn {s, f} -> s <= p and p <= f end) |> Enum.sort()
        assert Enum.sort(IntervalTree.enclosing(tree, p)) == expected
        assert Enum.sort(IntervalTree.overlapping(tree, {p, p})) == expected
      end
    end
  end

  test "queries match a brute-force scan after every single insertion" do
    ivs = arbitrary(60)

    _ =
      Enum.reduce(ivs, {IntervalTree.new(), []}, fn iv, {tree, seen} ->
        tree = IntervalTree.insert(tree, iv)
        seen = [iv | seen]

        for p <- [0, 5, 155, 300, 595, 700] do
          expected = seen |> Enum.filter(fn {s, f} -> s <= p and p <= f end) |> Enum.sort()
          assert Enum.sort(IntervalTree.enclosing(tree, p)) == expected
        end

        {tree, seen}
      end)
  end

  test "many copies of one interval are all stored and returned" do
    tree =
      Enum.reduce(1..50, IntervalTree.new(), fn _i, acc ->
        IntervalTree.insert(acc, {5, 9})
      end)

    assert length(IntervalTree.enclosing(tree, 7)) == 50
    assert length(IntervalTree.enclosing(tree, 5)) == 50
    assert length(IntervalTree.overlapping(tree, {9, 12})) == 50
    assert IntervalTree.overlapping(tree, {10, 12}) == []
    assert IntervalTree.enclosing(tree, 4) == []
  end

  test "zig-zag inserts keep every interval and every endpoint queryable" do
    ivs = zigzag(64)
    tree = build(ivs)

    assert Enum.sort(IntervalTree.overlapping(tree, {0, 10_000})) == Enum.sort(ivs)

    for {s, f} <- ivs do
      assert IntervalTree.enclosing(tree, s) == [{s, f}]
      assert IntervalTree.enclosing(tree, f) == [{s, f}]
    end
  end

  # -------------------------------------------------------
  # Pseudo-random differential check against a brute-force oracle
  # -------------------------------------------------------

  test "queries agree with a brute-force scan on a pseudo-random workload" do
    ivs = random_intervals(300)
    tree = build(ivs)

    for p <- 0..200//7 do
      expected = ivs |> Enum.filter(fn {s, f} -> s <= p and p <= f end) |> Enum.sort()
      assert Enum.sort(IntervalTree.enclosing(tree, p)) == expected
      assert Enum.sort(IntervalTree.overlapping(tree, {p, p})) == expected
    end

    for qs <- 0..200//11 do
      qf = qs + 13
      expected = ivs |> Enum.filter(fn {s, f} -> s <= qf and f >= qs end) |> Enum.sort()
      assert Enum.sort(IntervalTree.overlapping(tree, {qs, qf})) == expected
    end
  end

  # -------------------------------------------------------
  # Balance / complexity contract
  # -------------------------------------------------------
  # The documented costs are O(log n) for insert/2 and O(log n + k) for the
  # queries, which only holds while insert/2 keeps the tree balanced. These
  # tests compare the work done on a tree of @big intervals against the very
  # same work on a tree of @small intervals built exactly the same way, so the
  # per-node constant factor cancels out. With balancing intact, growing the
  # tree 32x costs well under 4x more work; if insert/2 stops rebalancing, the
  # tree degenerates into a list and the cost grows ~32x, i.e. linearly.

  test "enclosing on a far-right point stays logarithmic as the tree grows (ascending inserts)" do
    small = build(ascending(@small))
    big = build(ascending(@big))

    {r_small, res_small} = measure(fn -> IntervalTree.enclosing(small, (@small - 1) * 10 + 5) end)
    {r_big, res_big} = measure(fn -> IntervalTree.enclosing(big, (@big - 1) * 10 + 5) end)

    assert res_small == [{(@small - 1) * 10, (@small - 1) * 10 + 9}]
    assert res_big == [{(@big - 1) * 10, (@big - 1) * 10 + 9}]
    assert r_big <= 4 * r_small + 1_000
  end

  test "insert of a new largest interval stays logarithmic as the tree grows (ascending)" do
    small = build(ascending(@small))
    big = build(ascending(@big))

    {r_small, small2} =
      measure(fn -> IntervalTree.insert(small, {@small * 10, @small * 10 + 9}) end)

    {r_big, big2} = measure(fn -> IntervalTree.insert(big, {@big * 10, @big * 10 + 9}) end)

    assert IntervalTree.enclosing(small2, @small * 10 + 5) == [{@small * 10, @small * 10 + 9}]
    assert IntervalTree.enclosing(big2, @big * 10 + 5) == [{@big * 10, @big * 10 + 9}]
    assert r_big <= 4 * r_small + 1_000
  end

  test "queries and inserts stay logarithmic when intervals arrive in descending order" do
    small = build(Enum.reverse(ascending(@small)))
    big = build(Enum.reverse(ascending(@big)))

    {rq_small, res_small} = measure(fn -> IntervalTree.enclosing(small, 5) end)
    {rq_big, res_big} = measure(fn -> IntervalTree.enclosing(big, 5) end)

    assert res_small == [{0, 9}]
    assert res_big == [{0, 9}]
    assert rq_big <= 4 * rq_small + 1_000

    {ri_small, small2} = measure(fn -> IntervalTree.insert(small, {-10, -1}) end)
    {ri_big, big2} = measure(fn -> IntervalTree.insert(big, {-10, -1}) end)

    assert IntervalTree.enclosing(small2, -5) == [{-10, -1}]
    assert IntervalTree.enclosing(big2, -5) == [{-10, -1}]
    assert ri_big <= 4 * ri_small + 1_000
  end

  # -------------------------------------------------------
  # Balance, probed from the *other* side of each build order
  # -------------------------------------------------------
  # The two tests above probe an ascending build from the right and a descending
  # build from the left — exactly the ends those builds leave near the root even
  # when rebalancing is broken. A rebalancing bug that leans the tree the other
  # way (or over-rotates on every insert) is invisible from those probes but
  # makes the *opposite* end sit ~n levels deep. These mirrored probes pin the
  # documented O(log n + k) cost from both directions for every build order.

  test "enclosing on a far-left point stays logarithmic as the tree grows (ascending inserts)" do
    small = build(ascending(@small))
    big = build(ascending(@big))

    {r_small, res_small} = measure(fn -> IntervalTree.enclosing(small, 5) end)
    {r_big, res_big} = measure(fn -> IntervalTree.enclosing(big, 5) end)

    assert res_small == [{0, 9}]
    assert res_big == [{0, 9}]
    assert r_big <= 4 * r_small + 1_000
  end

  test "enclosing on a far-right point stays logarithmic when inserts arrive descending" do
    small = build(Enum.reverse(ascending(@small)))
    big = build(Enum.reverse(ascending(@big)))

    {r_small, res_small} = measure(fn -> IntervalTree.enclosing(small, (@small - 1) * 10 + 5) end)
    {r_big, res_big} = measure(fn -> IntervalTree.enclosing(big, (@big - 1) * 10 + 5) end)

    assert res_small == [{(@small - 1) * 10, (@small - 1) * 10 + 9}]
    assert res_big == [{(@big - 1) * 10, (@big - 1) * 10 + 9}]
    assert r_big <= 4 * r_small + 1_000
  end

  test "insert of a new smallest interval stays logarithmic (ascending build)" do
    small = build(ascending(@small))
    big = build(ascending(@big))

    {r_small, small2} = measure(fn -> IntervalTree.insert(small, {-10, -1}) end)
    {r_big, big2} = measure(fn -> IntervalTree.insert(big, {-10, -1}) end)

    assert IntervalTree.enclosing(small2, -5) == [{-10, -1}]
    assert IntervalTree.enclosing(big2, -5) == [{-10, -1}]
    assert r_big <= 4 * r_small + 1_000
  end

  test "insert of a new largest interval stays logarithmic (descending build)" do
    small = build(Enum.reverse(ascending(@small)))
    big = build(Enum.reverse(ascending(@big)))

    {r_small, small2} =
      measure(fn -> IntervalTree.insert(small, {@small * 10, @small * 10 + 9}) end)

    {r_big, big2} = measure(fn -> IntervalTree.insert(big, {@big * 10, @big * 10 + 9}) end)

    assert IntervalTree.enclosing(small2, @small * 10 + 5) == [{@small * 10, @small * 10 + 9}]
    assert IntervalTree.enclosing(big2, @big * 10 + 5) == [{@big * 10, @big * 10 + 9}]
    assert r_big <= 4 * r_small + 1_000
  end

  test "inserting into the middle of the key range stays logarithmic (ascending build)" do
    small = build(ascending(@small))
    big = build(ascending(@big))
    s_mid = div(@small, 2) * 10
    b_mid = div(@big, 2) * 10

    {r_small, small2} = measure(fn -> IntervalTree.insert(small, {s_mid + 3, s_mid + 4}) end)
    {r_big, big2} = measure(fn -> IntervalTree.insert(big, {b_mid + 3, b_mid + 4}) end)

    assert Enum.sort(IntervalTree.enclosing(small2, s_mid + 3)) ==
             [{s_mid, s_mid + 9}, {s_mid + 3, s_mid + 4}]

    assert Enum.sort(IntervalTree.enclosing(big2, b_mid + 3)) ==
             [{b_mid, b_mid + 9}, {b_mid + 3, b_mid + 4}]

    assert r_big <= 4 * r_small + 1_000
  end

  test "overlapping a narrow range at either end stays logarithmic (ascending inserts)" do
    small = build(ascending(@small))
    big = build(ascending(@big))

    {rl_small, res_l_small} = measure(fn -> IntervalTree.overlapping(small, {3, 6}) end)
    {rl_big, res_l_big} = measure(fn -> IntervalTree.overlapping(big, {3, 6}) end)

    assert res_l_small == [{0, 9}]
    assert res_l_big == [{0, 9}]
    assert rl_big <= 4 * rl_small + 1_000

    s_last = (@small - 1) * 10
    b_last = (@big - 1) * 10

    {rr_small, res_r_small} =
      measure(fn -> IntervalTree.overlapping(small, {s_last + 3, s_last + 6}) end)

    {rr_big, res_r_big} =
      measure(fn -> IntervalTree.overlapping(big, {b_last + 3, b_last + 6}) end)

    assert res_r_small == [{s_last, s_last + 9}]
    assert res_r_big == [{b_last, b_last + 9}]
    assert rr_big <= 4 * rr_small + 1_000
  end

  # -------------------------------------------------------
  # Balance under rotation-heavy and arbitrary insert orders
  # -------------------------------------------------------
  # A zig-zag order (smallest, largest, next smallest, next largest, ...) forces
  # both single and double rotations on nearly every insert; an arbitrary order
  # mixes all four rebalancing cases. Both must still leave every end of the key
  # range O(log n) deep, per the documented insert/query costs.

  test "far-left and far-right point queries stay logarithmic for zig-zag inserts" do
    small = build(zigzag(@small))
    big = build(zigzag(@big))

    {rl_small, res_l_small} = measure(fn -> IntervalTree.enclosing(small, 5) end)
    {rl_big, res_l_big} = measure(fn -> IntervalTree.enclosing(big, 5) end)

    assert res_l_small == [{0, 9}]
    assert res_l_big == [{0, 9}]
    assert rl_big <= 4 * rl_small + 1_000

    {rr_small, res_r_small} =
      measure(fn -> IntervalTree.enclosing(small, (@small - 1) * 10 + 5) end)

    {rr_big, res_r_big} = measure(fn -> IntervalTree.enclosing(big, (@big - 1) * 10 + 5) end)

    assert res_r_small == [{(@small - 1) * 10, (@small - 1) * 10 + 9}]
    assert res_r_big == [{(@big - 1) * 10, (@big - 1) * 10 + 9}]
    assert rr_big <= 4 * rr_small + 1_000
  end

  test "far-left and far-right point queries stay logarithmic for arbitrary inserts" do
    small = build(arbitrary(@small))
    big = build(arbitrary(@big))

    {rl_small, res_l_small} = measure(fn -> IntervalTree.enclosing(small, 5) end)
    {rl_big, res_l_big} = measure(fn -> IntervalTree.enclosing(big, 5) end)

    assert res_l_small == [{0, 9}]
    assert res_l_big == [{0, 9}]
    assert rl_big <= 4 * rl_small + 1_000

    {rr_small, res_r_small} =
      measure(fn -> IntervalTree.enclosing(small, (@small - 1) * 10 + 5) end)

    {rr_big, res_r_big} = measure(fn -> IntervalTree.enclosing(big, (@big - 1) * 10 + 5) end)

    assert res_r_small == [{(@small - 1) * 10, (@small - 1) * 10 + 9}]
    assert res_r_big == [{(@big - 1) * 10, (@big - 1) * 10 + 9}]
    assert rr_big <= 4 * rr_small + 1_000
  end

  test "every insertion order answers a mid-range point query with comparable work" do
    mid = div(@big, 2) * 10 + 5

    costs =
      for order <- [
            ascending(@big),
            Enum.reverse(ascending(@big)),
            zigzag(@big),
            arbitrary(@big)
          ] do
        tree = build(order)
        {r, res} = measure(fn -> IntervalTree.enclosing(tree, mid) end)
        assert res == [{mid - 5, mid + 4}]
        r
      end

    # Insertion order may change the tree's shape, but never its balance: the
    # same query must cost the same order of work whichever order built it.
    assert Enum.max(costs) <= 3 * Enum.min(costs) + 1_000
  end

  test "building the tree stays near-linearithmic for every insertion order" do
    for {label, small_list, big_list} <- [
          {"ascending", ascending(@small), ascending(@big)},
          {"descending", Enum.reverse(ascending(@small)), Enum.reverse(ascending(@big))},
          {"zig-zag", zigzag(@small), zigzag(@big)},
          {"arbitrary", arbitrary(@small), arbitrary(@big)}
        ] do
      {r_small, tree_small} = measure(fn -> build(small_list) end)
      {r_big, tree_big} = measure(fn -> build(big_list) end)

      assert IntervalTree.enclosing(tree_small, 5) == [{0, 9}]
      assert IntervalTree.enclosing(tree_big, 5) == [{0, 9}]

      # n inserts of O(log n) each: 32x the intervals costs ~55x the work. An
      # unbalanced tree makes each insert O(n), i.e. ~1000x the work overall.
      assert r_big <= 100 * r_small + 10_000, "#{label}: #{r_big} vs #{r_small}"
    end
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp build(intervals) do
    Enum.reduce(intervals, IntervalTree.new(), fn iv, acc -> IntervalTree.insert(acc, iv) end)
  end

  defp ascending(n), do: Enum.map(0..(n - 1), fn i -> {i * 10, i * 10 + 9} end)

  # Smallest, largest, next smallest, next largest, ... — a rotation-heavy order.
  defp zigzag(n) do
    list = ascending(n)
    {front, back} = Enum.split(list, div(n, 2))
    rev_back = Enum.reverse(back)

    pairs =
      front
      |> Enum.zip(rev_back)
      |> Enum.flat_map(fn {a, b} -> [a, b] end)

    pairs ++ Enum.drop(rev_back, length(front))
  end

  # A deterministic scramble of the ascending order (no test-run variance).
  defp arbitrary(n) do
    n
    |> ascending()
    |> Enum.sort_by(fn {s, _f} -> rem(s * 2_654_435_761, 1_000_003) end)
  end

  # Every ordering of a (small) list — used to drive every rebalancing path.
  defp permutations([]), do: [[]]

  defp permutations(list) do
    for head <- list, tail <- permutations(list -- [head]), do: [head | tail]
  end

  # Work done by `fun`, in reductions of the calling process. Reductions are a
  # deterministic count of function calls, so this measures algorithmic cost
  # without depending on machine speed or load.
  defp measure(fun) do
    {:reductions, r0} = Process.info(self(), :reductions)
    result = fun.()
    {:reductions, r1} = Process.info(self(), :reductions)
    {r1 - r0, result}
  end

  # Deterministic pseudo-random intervals (a small LCG — no test-run variance).
  defp random_intervals(n) do
    42
    |> lcg_values(2 * n, [])
    |> Enum.chunk_every(2)
    |> Enum.map(fn [a, b] -> {min(a, b), max(a, b)} end)
  end

  defp lcg_values(_seed, 0, acc), do: Enum.reverse(acc)

  defp lcg_values(seed, n, acc) do
    next = rem(seed * 1_103_515_245 + 12_345, 2_147_483_648)
    lcg_values(next, n - 1, [rem(next, 200) | acc])
  end
end
