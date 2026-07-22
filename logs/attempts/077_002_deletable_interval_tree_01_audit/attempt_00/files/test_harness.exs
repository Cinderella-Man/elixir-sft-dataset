defmodule DeletableIntervalTreeTest do
  use ExUnit.Case, async: false

  alias DeletableIntervalTree, as: T

  defp build(intervals) do
    Enum.reduce(intervals, T.new(), fn iv, acc -> T.insert(acc, iv) end)
  end

  # ---------------------------------------------------------------
  # Empty tree
  # ---------------------------------------------------------------

  test "empty tree queries" do
    tree = T.new()
    assert [] = T.overlapping(tree, {1, 10})
    assert [] = T.enclosing(tree, 5)
    assert T.size(tree) == 0
    refute T.member?(tree, {1, 2})
  end

  test "delete on empty tree reports not_found" do
    assert {:error, :not_found} = T.delete(T.new(), {1, 2})
  end

  # ---------------------------------------------------------------
  # Basic query behaviour (parity with a plain interval tree)
  # ---------------------------------------------------------------

  test "overlapping returns only matching intervals" do
    tree = build([{1, 2}, {5, 8}, {10, 15}, {20, 25}])
    result = T.overlapping(tree, {6, 12})
    assert length(result) == 2
    assert {5, 8} in result
    assert {10, 15} in result
  end

  test "touching intervals overlap" do
    tree = build([{1, 5}, {5, 10}])
    result = T.overlapping(tree, {5, 5})
    assert length(result) == 2
    assert {1, 5} in result
    assert {5, 10} in result
  end

  test "enclosing returns all intervals covering the point" do
    tree = build([{1, 10}, {3, 7}, {6, 15}, {20, 30}])
    result = T.enclosing(tree, 6)
    assert length(result) == 3
    refute {20, 30} in result
  end

  test "degenerate interval found by exact point" do
    tree = build([{4, 4}])
    assert [{4, 4}] = T.enclosing(tree, 4)
    assert [] = T.enclosing(tree, 5)
  end

  # ---------------------------------------------------------------
  # member?
  # ---------------------------------------------------------------

  test "member? reflects presence" do
    tree = build([{1, 5}, {10, 20}])
    assert T.member?(tree, {1, 5})
    assert T.member?(tree, {10, 20})
    refute T.member?(tree, {1, 6})
    refute T.member?(tree, {2, 5})
  end

  # ---------------------------------------------------------------
  # delete — success and failure semantics
  # ---------------------------------------------------------------

  test "delete removes an existing interval and returns :ok tuple" do
    tree = build([{1, 5}, {10, 20}, {30, 40}])
    assert {:ok, tree2} = T.delete(tree, {10, 20})
    refute T.member?(tree2, {10, 20})
    assert T.size(tree2) == 2
    assert [] = T.overlapping(tree2, {12, 15})
  end

  test "delete of absent interval returns error and leaves tree usable" do
    tree = build([{1, 5}, {10, 20}])
    assert {:error, :not_found} = T.delete(tree, {2, 9})
    # original still intact
    assert T.member?(tree, {1, 5})
    assert T.size(tree) == 2
  end

  test "delete removes only one of two identical intervals" do
    tree = build([{2, 8}, {2, 8}])
    assert T.size(tree) == 2
    assert {:ok, tree2} = T.delete(tree, {2, 8})
    assert T.size(tree2) == 1
    assert T.member?(tree2, {2, 8})
    assert [{2, 8}] = T.overlapping(tree2, {1, 10})
    assert {:ok, tree3} = T.delete(tree2, {2, 8})
    assert T.size(tree3) == 0
    assert {:error, :not_found} = T.delete(tree3, {2, 8})
  end

  # ---------------------------------------------------------------
  # Persistence — delete does not mutate the original
  # ---------------------------------------------------------------

  test "delete is non-destructive" do
    t1 = build([{1, 5}, {10, 20}])
    {:ok, t2} = T.delete(t1, {1, 5})

    # original still has the interval
    assert T.member?(t1, {1, 5})
    assert [{1, 5}] = T.overlapping(t1, {1, 3})

    # new tree does not
    refute T.member?(t2, {1, 5})
    assert [] = T.overlapping(t2, {1, 3})
  end

  # ---------------------------------------------------------------
  # Augmentation correctness after many deletes (max_finish pruning)
  # ---------------------------------------------------------------

  test "queries stay correct after interleaved inserts and deletes at scale" do
    tree =
      Enum.reduce(0..199, T.new(), fn i, acc ->
        T.insert(acc, {i * 10, i * 10 + 9})
      end)

    assert T.size(tree) == 200

    # Delete every even-indexed interval.
    tree =
      Enum.reduce(0..199//2, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i * 10, i * 10 + 9})
        acc2
      end)

    assert T.size(tree) == 100

    # {90,99} was even-indexed (i=9? -> 9 is odd, kept). Verify a kept one.
    assert T.member?(tree, {90, 99})
    # {100,109} is i=10 (even) -> deleted
    refute T.member?(tree, {100, 109})

    # Overlap query that would have touched three intervals now touches two kept ones.
    result = T.overlapping(tree, {95, 115})
    assert {90, 99} in result
    refute {100, 109} in result
    assert {110, 119} in result

    # Point query on a kept interval.
    assert [{150, 159}] = T.enclosing(tree, 155)
  end

  test "deleting the root repeatedly keeps the tree valid" do
    tree = build(for i <- 1..50, do: {i, i + 3})

    tree =
      Enum.reduce(1..50, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i, i + 3})
        acc2
      end)

    assert T.size(tree) == 0
    assert [] = T.overlapping(tree, {1, 1000})
  end

  test "insert is non-destructive and every earlier tree stays queryable" do
    t1 = build([{1, 5}])
    t2 = T.insert(t1, {10, 20})
    t3 = T.insert(t2, {2, 3})

    assert T.size(t1) == 1
    refute T.member?(t1, {10, 20})
    assert [{1, 5}] = T.overlapping(t1, {0, 100})
    assert [] = T.enclosing(t1, 15)

    assert T.size(t2) == 2
    refute T.member?(t2, {2, 3})
    assert T.member?(t2, {10, 20})
    assert [{10, 20}] = T.enclosing(t2, 15)

    assert T.size(t3) == 3
    assert T.member?(t3, {2, 3})
  end

  test "both stored copies of a duplicate interval are returned by queries" do
    tree = build([{2, 8}, {2, 8}, {30, 40}])

    assert T.size(tree) == 3
    assert T.member?(tree, {2, 8})
    assert Enum.sort(T.overlapping(tree, {1, 10})) == [{2, 8}, {2, 8}]
    assert Enum.sort(T.enclosing(tree, 5)) == [{2, 8}, {2, 8}]
    assert Enum.sort(T.overlapping(tree, {0, 100})) == [{2, 8}, {2, 8}, {30, 40}]
  end

  test "pruned queries agree with brute force after scripted inserts and deletes" do
    intervals =
      for i <- 0..119 do
        s = rem(i * 37, 100)
        {s, s + rem(i * 13, 20)}
      end

    tree = build(intervals)
    to_delete = Enum.take_every(intervals, 3)

    {tree, remaining} =
      Enum.reduce(to_delete, {tree, intervals}, fn iv, {acc, rest} ->
        {:ok, acc2} = T.delete(acc, iv)
        {acc2, List.delete(rest, iv)}
      end)

    assert T.size(tree) == length(remaining)

    for qs <- 0..120//7 do
      qf = qs + 9
      expected = Enum.filter(remaining, fn {s, f} -> s <= qf and f >= qs end)
      assert Enum.sort(T.overlapping(tree, {qs, qf})) == Enum.sort(expected)
    end

    for p <- 0..120//11 do
      expected = Enum.filter(remaining, fn {s, f} -> s <= p and p <= f end)
      assert Enum.sort(T.enclosing(tree, p)) == Enum.sort(expected)
    end
  end

  test "degenerate intervals support overlap, membership and one-at-a-time deletion" do
    tree = build([{4, 4}, {4, 4}, {7, 7}])

    assert T.member?(tree, {4, 4})
    assert Enum.sort(T.overlapping(tree, {4, 4})) == [{4, 4}, {4, 4}]
    assert Enum.sort(T.overlapping(tree, {3, 8})) == [{4, 4}, {4, 4}, {7, 7}]

    assert {:ok, tree2} = T.delete(tree, {4, 4})
    assert T.size(tree2) == 2
    assert [{4, 4}] = T.enclosing(tree2, 4)

    assert {:ok, tree3} = T.delete(tree2, {4, 4})
    refute T.member?(tree3, {4, 4})
    assert {:error, :not_found} = T.delete(tree3, {4, 4})
    assert [{7, 7}] = T.overlapping(tree3, {0, 100})
  end

  test "enclosing includes both endpoints and excludes points just outside" do
    tree = build([{1, 10}, {12, 20}])

    assert [{1, 10}] = T.enclosing(tree, 1)
    assert [{1, 10}] = T.enclosing(tree, 10)
    assert [] = T.enclosing(tree, 0)
    assert [] = T.enclosing(tree, 11)
    assert [{12, 20}] = T.enclosing(tree, 12)
    assert [{12, 20}] = T.enclosing(tree, 20)
    assert [] = T.enclosing(tree, 21)
  end

  test "deleting the widest interval keeps later queries correct" do
    tree = build([{0, 1000}, {5, 6}, {10, 11}, {20, 21}, {30, 31}, {40, 41}])

    assert {:ok, tree2} = T.delete(tree, {0, 1000})
    refute T.member?(tree2, {0, 1000})
    assert [] = T.enclosing(tree2, 500)
    assert [{20, 21}] = T.overlapping(tree2, {15, 25})

    assert Enum.sort(T.overlapping(tree2, {0, 1000})) ==
             [{5, 6}, {10, 11}, {20, 21}, {30, 31}, {40, 41}]

    assert T.member?(tree, {0, 1000})
    assert [{0, 1000}] = T.enclosing(tree, 500)
  end
end
