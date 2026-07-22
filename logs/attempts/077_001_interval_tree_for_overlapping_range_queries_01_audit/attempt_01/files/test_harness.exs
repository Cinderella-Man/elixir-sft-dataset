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
  # Helpers
  # -------------------------------------------------------

  defp build(intervals) do
    Enum.reduce(intervals, IntervalTree.new(), fn iv, acc -> IntervalTree.insert(acc, iv) end)
  end

  defp ascending(n), do: Enum.map(0..(n - 1), fn i -> {i * 10, i * 10 + 9} end)

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
