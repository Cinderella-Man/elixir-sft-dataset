# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

```elixir
defmodule IntervalRegistryTest do
  use ExUnit.Case, async: false

  # Large enough that an unbalanced (linear-depth) tree needs quadratic work.
  @big 10_000

  setup do
    {:ok, pid} = IntervalRegistry.start_link()

    on_exit(fn ->
      if Process.alive?(pid), do: IntervalRegistry.stop(pid)
    end)

    %{server: pid}
  end

  # ---------------------------------------------------------------
  # Empty registry
  # ---------------------------------------------------------------

  test "empty registry queries", %{server: s} do
    assert [] = IntervalRegistry.overlapping(s, {1, 10})
    assert [] = IntervalRegistry.enclosing(s, 5)
    assert IntervalRegistry.stab_count(s, 5) == 0
    assert IntervalRegistry.size(s) == 0
  end

  # ---------------------------------------------------------------
  # Insert returns ids; queries reflect stored intervals
  # ---------------------------------------------------------------

  test "insert returns unique ids", %{server: s} do
    {:ok, id1} = IntervalRegistry.insert(s, {1, 5})
    {:ok, id2} = IntervalRegistry.insert(s, {1, 5})
    {:ok, id3} = IntervalRegistry.insert(s, {10, 20})

    assert id1 != id2
    assert id2 != id3
    assert IntervalRegistry.size(s) == 3
  end

  test "ids start at 1 and advance by exactly one per insert", %{server: s} do
    assert {:ok, 1} = IntervalRegistry.insert(s, {1, 2})
    assert {:ok, 2} = IntervalRegistry.insert(s, {1, 2})
    assert {:ok, 3} = IntervalRegistry.insert(s, {5, 9})

    # Removing an id does not rewind or reuse the counter.
    assert :ok = IntervalRegistry.remove(s, 2)
    assert {:ok, 4} = IntervalRegistry.insert(s, {0, 0})

    assert :ok = IntervalRegistry.remove(s, 1)
    assert :ok = IntervalRegistry.remove(s, 3)
    assert :ok = IntervalRegistry.remove(s, 4)
    assert IntervalRegistry.size(s) == 0

    assert {:ok, 5} = IntervalRegistry.insert(s, {2, 2})
    assert [{2, 2}] = IntervalRegistry.enclosing(s, 2)
  end

  test "a fresh server restarts the id sequence at 1", %{server: s} do
    assert {:ok, 1} = IntervalRegistry.insert(s, {3, 4})
    assert {:ok, 2} = IntervalRegistry.insert(s, {3, 4})

    {:ok, other} = IntervalRegistry.start_link()
    assert {:ok, 1} = IntervalRegistry.insert(other, {7, 8})
    assert {:ok, 2} = IntervalRegistry.insert(other, {7, 8})
    assert :ok = IntervalRegistry.stop(other)
  end

  test "overlapping returns sorted matches", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, _} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _} = IntervalRegistry.insert(s, {10, 15})

    assert [{1, 5}, {3, 8}] = IntervalRegistry.overlapping(s, {4, 6})
    assert [{3, 8}] = IntervalRegistry.overlapping(s, {8, 9})
    assert [] = IntervalRegistry.overlapping(s, {20, 25})
  end

  test "touching intervals overlap", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, _} = IntervalRegistry.insert(s, {5, 10})
    assert [{1, 5}, {5, 10}] = IntervalRegistry.overlapping(s, {5, 5})
  end

  test "query boundaries are inclusive at both ends", %{server: s} do
    for iv <- [{1, 5}, {5, 6}, {6, 10}, {2, 3}, {10, 12}] do
      {:ok, _} = IntervalRegistry.insert(s, iv)
    end

    assert IntervalRegistry.overlapping(s, {5, 5}) == [{1, 5}, {5, 6}]
    assert IntervalRegistry.overlapping(s, {6, 6}) == [{5, 6}, {6, 10}]
    assert IntervalRegistry.overlapping(s, {3, 5}) == [{1, 5}, {2, 3}, {5, 6}]
    assert IntervalRegistry.overlapping(s, {12, 99}) == [{10, 12}]
    assert IntervalRegistry.overlapping(s, {0, 1}) == [{1, 5}]
    assert IntervalRegistry.stab_count(s, 10) == 2
    assert IntervalRegistry.stab_count(s, 5) == 2
  end

  test "enclosing and stab_count", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 10})
    {:ok, _} = IntervalRegistry.insert(s, {3, 7})
    {:ok, _} = IntervalRegistry.insert(s, {6, 15})
    {:ok, _} = IntervalRegistry.insert(s, {20, 30})

    assert [{1, 10}, {3, 7}, {6, 15}] = IntervalRegistry.enclosing(s, 6)
    assert IntervalRegistry.stab_count(s, 6) == 3
    assert IntervalRegistry.stab_count(s, 25) == 1
    assert IntervalRegistry.stab_count(s, 100) == 0
  end

  test "degenerate interval", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {4, 4})
    assert [{4, 4}] = IntervalRegistry.enclosing(s, 4)
    assert [] = IntervalRegistry.enclosing(s, 5)
    assert IntervalRegistry.stab_count(s, 4) == 1
  end

  # ---------------------------------------------------------------
  # remove semantics
  # ---------------------------------------------------------------

  test "remove deletes exactly the stored interval by id", %{server: s} do
    {:ok, id_a} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _id_b} = IntervalRegistry.insert(s, {3, 8})

    assert IntervalRegistry.size(s) == 2
    assert :ok = IntervalRegistry.remove(s, id_a)
    assert IntervalRegistry.size(s) == 1
    # one copy remains
    assert [{3, 8}] = IntervalRegistry.overlapping(s, {1, 10})
  end

  test "remove of unknown id returns not_found", %{server: s} do
    assert {:error, :not_found} = IntervalRegistry.remove(s, 9999)
    {:ok, id} = IntervalRegistry.insert(s, {1, 2})
    assert :ok = IntervalRegistry.remove(s, id)
    # removing again fails
    assert {:error, :not_found} = IntervalRegistry.remove(s, id)
  end

  test "remove updates overlap results", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, mid} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _} = IntervalRegistry.insert(s, {10, 15})

    assert :ok = IntervalRegistry.remove(s, mid)
    assert [{1, 5}] = IntervalRegistry.overlapping(s, {4, 6})
  end

  # ---------------------------------------------------------------
  # stop/1 — actually terminates the running server
  # ---------------------------------------------------------------

  test "stop terminates the running server", %{server: s} do
    assert Process.alive?(s)
    ref = Process.monitor(s)

    assert :ok = IntervalRegistry.stop(s)

    assert_receive {:DOWN, ^ref, :process, ^s, _reason}, 1_000
    refute Process.alive?(s)
  end

  test "stop shuts down an independently started server", %{server: _s} do
    {:ok, other} = IntervalRegistry.start_link()
    {:ok, _} = IntervalRegistry.insert(other, {1, 2})
    assert IntervalRegistry.size(other) == 1

    assert Process.alive?(other)
    assert :ok = IntervalRegistry.stop(other)
    refute Process.alive?(other)

    # A stopped server no longer answers calls.
    assert catch_exit(IntervalRegistry.size(other))
  end

  # ---------------------------------------------------------------
  # Concurrency — many client processes mutate the shared server
  # ---------------------------------------------------------------

  test "concurrent inserts are all recorded consistently", %{server: s} do
    1..200
    |> Task.async_stream(fn i -> IntervalRegistry.insert(s, {i, i + 5}) end,
      max_concurrency: 20,
      ordered: false
    )
    |> Enum.to_list()

    assert IntervalRegistry.size(s) == 200

    # Intervals {i, i+5} cover point 10 iff i <= 10 <= i+5, i.e. i in 5..10 → 6 of them.
    assert IntervalRegistry.stab_count(s, 10) == 6
  end

  test "concurrent inserts and removes leave a consistent count", %{server: s} do
    ids =
      1..100
      |> Task.async_stream(
        fn i ->
          {:ok, id} = IntervalRegistry.insert(s, {i, i + 2})
          id
        end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, id} -> id end)

    assert IntervalRegistry.size(s) == 100

    to_remove = Enum.take_every(ids, 2)

    to_remove
    |> Task.async_stream(fn id -> IntervalRegistry.remove(s, id) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Enum.to_list()

    assert IntervalRegistry.size(s) == 100 - length(to_remove)
  end

  test "start_link registers under a :name and the api works through that name" do
    name = :interval_registry_promise_named
    {:ok, pid} = IntervalRegistry.start_link(name: name)
    assert Process.whereis(name) == pid

    {:ok, id} = IntervalRegistry.insert(name, {2, 6})
    assert IntervalRegistry.size(name) == 1
    assert [{2, 6}] = IntervalRegistry.overlapping(name, {6, 9})
    assert IntervalRegistry.stab_count(name, 4) == 1
    assert :ok = IntervalRegistry.remove(name, id)
    assert IntervalRegistry.size(name) == 0

    ref = Process.monitor(pid)
    assert :ok = IntervalRegistry.stop(name)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end

  test "overlapping matches a brute-force scan over a large mixed tree", %{server: s} do
    intervals =
      for i <- 1..120 do
        start = rem(i * 37, 100)
        {start, start + rem(i * 13, 20)}
      end

    Enum.each(intervals, fn iv -> {:ok, _} = IntervalRegistry.insert(s, iv) end)
    assert IntervalRegistry.size(s) == 120

    queries = [{0, 0}, {5, 5}, {40, 50}, {-10, 3}, {99, 200}, {0, 200}, {200, 300}]

    for {qs, qf} = q <- queries do
      expected =
        intervals
        |> Enum.filter(fn {a, b} -> a <= qf and b >= qs end)
        |> Enum.sort()

      assert IntervalRegistry.overlapping(s, q) == expected
    end
  end

  test "enclosing sorts results and includes both endpoints of each interval", %{server: s} do
    for iv <- [{9, 12}, {1, 5}, {5, 5}, {-3, 1}, {2, 9}] do
      {:ok, _} = IntervalRegistry.insert(s, iv)
    end

    assert IntervalRegistry.enclosing(s, 1) == [{-3, 1}, {1, 5}]
    assert IntervalRegistry.enclosing(s, 5) == [{1, 5}, {2, 9}, {5, 5}]
    assert IntervalRegistry.enclosing(s, 9) == [{2, 9}, {9, 12}]
    assert IntervalRegistry.enclosing(s, 12) == [{9, 12}]
    assert IntervalRegistry.enclosing(s, 13) == []
  end

  test "queries match the surviving set after concurrent inserts and removes", %{server: s} do
    pairs =
      1..150
      |> Task.async_stream(fn i -> {i, IntervalRegistry.insert(s, {i, i + 10})} end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, {i, {:ok, id}}} -> {i, id} end)

    {kept, dropped} = Enum.split_with(pairs, fn {i, _id} -> rem(i, 3) == 0 end)

    dropped
    |> Task.async_stream(fn {_i, id} -> :ok = IntervalRegistry.remove(s, id) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Enum.to_list()

    expected = kept |> Enum.map(fn {i, _id} -> {i, i + 10} end) |> Enum.sort()
    stabbed = Enum.filter(expected, fn {a, b} -> a <= 60 and 60 <= b end)

    assert IntervalRegistry.size(s) == length(kept)
    assert IntervalRegistry.overlapping(s, {1, 200}) == expected
    assert IntervalRegistry.enclosing(s, 60) == stabbed
    assert IntervalRegistry.stab_count(s, 60) == length(stabbed)
  end

  test "ids are unique across concurrent clients and not reused after removal", %{server: s} do
    ids =
      1..100
      |> Task.async_stream(fn i -> IntervalRegistry.insert(s, {i, i}) end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, id}} -> id end)

    assert Enum.all?(ids, &is_integer/1)
    assert length(Enum.uniq(ids)) == 100

    Enum.each(ids, fn id -> assert :ok = IntervalRegistry.remove(s, id) end)
    assert IntervalRegistry.size(s) == 0

    {:ok, fresh} = IntervalRegistry.insert(s, {1, 1})
    refute fresh in ids
  end

  test "insert rejects a reversed interval instead of storing it", %{server: s} do
    assert_raise FunctionClauseError, fn -> IntervalRegistry.insert(s, {7, 3}) end
    assert IntervalRegistry.size(s) == 0

    {:ok, _} = IntervalRegistry.insert(s, {3, 7})
    assert IntervalRegistry.size(s) == 1
    assert [{3, 7}] = IntervalRegistry.overlapping(s, {7, 7})
  end

  # ---------------------------------------------------------------
  # Self-balancing — sorted insertion orders are the worst case for an
  # unbalanced BST (depth n, so n inserts cost O(n^2)). A tree that keeps
  # its height logarithmic finishes these in well under a second; one that
  # never rebalances needs minutes and blows the deadline below.
  # ---------------------------------------------------------------

  test "ascending inserts stay logarithmic and query correctly" do
    {:ok, srv} = IntervalRegistry.start_link()

    task =
      Task.async(fn ->
        Enum.each(1..@big, fn i -> {:ok, _} = IntervalRegistry.insert(srv, {i, i + 1}) end)
        :inserted
      end)

    assert {:ok, :inserted} = Task.yield(task, 20_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == @big
    assert IntervalRegistry.stab_count(srv, 5_000) == 2
    assert IntervalRegistry.enclosing(srv, 5_000) == [{4_999, 5_000}, {5_000, 5_001}]
    assert IntervalRegistry.overlapping(srv, {1, 1}) == [{1, 2}]
    assert IntervalRegistry.enclosing(srv, @big + 1) == [{@big, @big + 1}]
    assert IntervalRegistry.stab_count(srv, @big + 2) == 0

    assert :ok = IntervalRegistry.stop(srv)
  end

  test "descending inserts stay logarithmic and query correctly" do
    {:ok, srv} = IntervalRegistry.start_link()

    task =
      Task.async(fn ->
        Enum.each(@big..1//-1, fn i -> {:ok, _} = IntervalRegistry.insert(srv, {i, i}) end)
        :inserted
      end)

    assert {:ok, :inserted} = Task.yield(task, 20_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == @big
    assert IntervalRegistry.stab_count(srv, 7_777) == 1
    assert IntervalRegistry.enclosing(srv, 1) == [{1, 1}]
    assert IntervalRegistry.enclosing(srv, 0) == []
    assert IntervalRegistry.overlapping(srv, {3, 6}) == [{3, 3}, {4, 4}, {5, 5}, {6, 6}]

    assert :ok = IntervalRegistry.stop(srv)
  end

  test "interleaved inserts and removes keep the tree balanced and consistent" do
    {:ok, srv} = IntervalRegistry.start_link()
    half = div(@big, 2)

    task =
      Task.async(fn ->
        ids =
          Enum.map(1..@big, fn i ->
            {:ok, id} = IntervalRegistry.insert(srv, {i, i + 3})
            {i, id}
          end)

        Enum.each(ids, fn {i, id} ->
          if i > half, do: :ok = IntervalRegistry.remove(srv, id)
        end)

        :done
      end)

    assert {:ok, :done} = Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == half
    assert IntervalRegistry.overlapping(srv, {half + 4, @big}) == []

    assert IntervalRegistry.enclosing(srv, half) == [
             {half - 3, half},
             {half - 2, half + 1},
             {half - 1, half + 2},
             {half, half + 3}
           ]

    assert IntervalRegistry.stab_count(srv, half) == 4

    assert :ok = IntervalRegistry.stop(srv)
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
