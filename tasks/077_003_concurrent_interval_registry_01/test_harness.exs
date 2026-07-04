defmodule IntervalRegistryTest do
  use ExUnit.Case, async: false

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
end