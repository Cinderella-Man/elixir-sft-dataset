defmodule PoolTest do
  use ExUnit.Case, async: false

  # --- helpers -------------------------------------------------------------

  # Checks out a connection from a *separate* process that stays alive until
  # told to release (or until it is killed). Returns {holder_pid, result}.
  defp spawn_holder(pool, timeout) do
    parent = self()

    pid =
      spawn(fn ->
        result = Pool.checkout(pool, timeout)
        send(parent, {:checked_out, self(), result})

        receive do
          :release -> :ok
        end
      end)

    assert_receive {:checked_out, ^pid, result}, 1_000
    {pid, result}
  end

  defp counting_create do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    create = fn ->
      n = Agent.get_and_update(counter, fn c -> {c, c + 1} end)
      {:conn, n}
    end

    {counter, create}
  end

  defp created(counter), do: Agent.get(counter, & &1)

  # --- basic checkout / checkin -------------------------------------------

  test "hands out distinct connections up to max_size" do
    start_supervised!({Pool, name: :pool_distinct, max_size: 2})

    assert {:ok, c1} = Pool.checkout(:pool_distinct, 100)
    assert {:ok, c2} = Pool.checkout(:pool_distinct, 100)
    assert c1 != c2
  end

  test "checkout all -> next times out -> checkin one -> next succeeds" do
    start_supervised!({Pool, name: :pool_basic, max_size: 2})

    assert {:ok, c1} = Pool.checkout(:pool_basic, 100)
    assert {:ok, _c2} = Pool.checkout(:pool_basic, 100)

    # Pool exhausted: the next checkout must time out cleanly.
    assert {:error, :timeout} = Pool.checkout(:pool_basic, 50)

    # Return one connection...
    assert :ok = Pool.checkin(:pool_basic, c1)

    # ...and now a checkout succeeds again, reusing the returned connection.
    assert {:ok, c3} = Pool.checkout(:pool_basic, 100)
    assert c3 == c1
  end

  test "checkin returns :ok and makes the connection available again" do
    start_supervised!({Pool, name: :pool_checkin, max_size: 1})

    assert {:ok, c} = Pool.checkout(:pool_checkin, 100)
    assert {:error, :timeout} = Pool.checkout(:pool_checkin, 20)
    assert :ok = Pool.checkin(:pool_checkin, c)
    assert {:ok, ^c} = Pool.checkout(:pool_checkin, 100)
  end

  # --- lazy creation -------------------------------------------------------

  test "connections are created lazily, never beyond max, and reused" do
    {counter, create} = counting_create()

    start_supervised!({Pool, name: :pool_lazy, min_size: 0, max_size: 3, create: create})

    # Nothing created eagerly when min_size is 0.
    assert created(counter) == 0

    assert {:ok, a} = Pool.checkout(:pool_lazy, 100)
    assert {:ok, _b} = Pool.checkout(:pool_lazy, 100)
    assert {:ok, _c} = Pool.checkout(:pool_lazy, 100)
    assert created(counter) == 3

    # At max: a further checkout times out and creates nothing new.
    assert {:error, :timeout} = Pool.checkout(:pool_lazy, 50)
    assert created(counter) == 3

    # Returned connections are reused, not recreated.
    assert :ok = Pool.checkin(:pool_lazy, a)
    assert {:ok, a2} = Pool.checkout(:pool_lazy, 100)
    assert a2 == a
    assert created(counter) == 3
  end

  test "min_size connections are created eagerly at startup" do
    {counter, create} = counting_create()

    start_supervised!({Pool, name: :pool_min, min_size: 2, max_size: 4, create: create})

    assert created(counter) == 2

    stats = Pool.stats(:pool_min)
    assert stats.total == 2
    assert stats.available == 2
    assert stats.in_use == 0
  end

  # --- stats ---------------------------------------------------------------

  test "stats reflects available / in_use / total" do
    start_supervised!({Pool, name: :pool_stats, min_size: 0, max_size: 3})

    assert %{available: 0, in_use: 0, total: 0, max: 3} = Pool.stats(:pool_stats)

    assert {:ok, c1} = Pool.checkout(:pool_stats, 100)
    s1 = Pool.stats(:pool_stats)
    assert s1.in_use == 1
    assert s1.total == 1
    assert s1.available == 0

    assert {:ok, _c2} = Pool.checkout(:pool_stats, 100)
    s2 = Pool.stats(:pool_stats)
    assert s2.in_use == 2
    assert s2.total == 2

    assert :ok = Pool.checkin(:pool_stats, c1)
    s3 = Pool.stats(:pool_stats)
    assert s3.in_use == 1
    assert s3.available == 1
    assert s3.total == 2
  end

  # --- blocking waiter served on checkin -----------------------------------

  test "a blocked checkout is served when another process checks in" do
    start_supervised!({Pool, name: :pool_wait, max_size: 2})

    {:ok, c1} = Pool.checkout(:pool_wait, 100)
    {:ok, _c2} = Pool.checkout(:pool_wait, 100)

    parent = self()

    _waiter =
      spawn(fn ->
        send(parent, {:result, Pool.checkout(:pool_wait, 1_000)})
      end)

    # Let the waiter block on an exhausted pool.
    Process.sleep(50)
    refute_received {:result, _}

    # Checking a connection in should unblock the waiter.
    assert :ok = Pool.checkin(:pool_wait, c1)
    assert_receive {:result, {:ok, _conn}}, 500
  end

  # --- crash reclamation ---------------------------------------------------

  test "a crashed holder's connection is reclaimed via monitoring" do
    start_supervised!({Pool, name: :pool_crash, min_size: 0, max_size: 1})

    {holder, result} = spawn_holder(:pool_crash, 1_000)
    assert {:ok, _conn} = result

    # Only one connection, and the (still-alive) holder owns it.
    assert {:error, :timeout} = Pool.checkout(:pool_crash, 50)

    # Kill the holder without it checking the connection back in.
    Process.exit(holder, :kill)

    # The pool must reclaim the connection and hand it out again.
    assert {:ok, _reclaimed} = Pool.checkout(:pool_crash, 1_000)

    stats = Pool.stats(:pool_crash)
    assert stats.total == 1
    assert stats.in_use == 1
    assert stats.available == 0
  end

  test "reclaimed connection is handed to a process already waiting" do
    start_supervised!({Pool, name: :pool_crash_wait, min_size: 0, max_size: 1})

    {holder, {:ok, _}} = spawn_holder(:pool_crash_wait, 1_000)

    parent = self()

    _waiter =
      spawn(fn ->
        send(parent, {:result, Pool.checkout(:pool_crash_wait, 1_000)})
      end)

    # Ensure the waiter is blocked before the holder dies.
    Process.sleep(50)
    refute_received {:result, _}

    Process.exit(holder, :kill)

    assert_receive {:result, {:ok, _conn}}, 1_000
  end
end
