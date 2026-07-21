defmodule OverflowPoolTest do
  use ExUnit.Case, async: false

  # --- helpers -------------------------------------------------------------

  defp spawn_holder(pool, timeout) do
    parent = self()

    pid =
      spawn(fn ->
        result = OverflowPool.checkout(pool, timeout)
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

  defp destroy_tracker do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    destroy = fn conn -> Agent.update(agent, fn d -> [conn | d] end) end
    destroyed = fn -> Enum.reverse(Agent.get(agent, & &1)) end
    {destroy, destroyed}
  end

  # --- eager base ----------------------------------------------------------

  test "creates :size connections eagerly at startup" do
    {counter, create} = counting_create()
    start_supervised!({OverflowPool, name: :op_eager, size: 3, max_overflow: 2, create: create})
    assert created(counter) == 3
    s = OverflowPool.stats(:op_eager)
    assert s.total == 3 and s.available == 3 and s.in_use == 0 and s.overflow == 0
  end

  # --- option defaults -----------------------------------------------------

  test "defaults to a base of 5 eager connections with no overflow allowed" do
    {counter, create} = counting_create()
    start_supervised!({OverflowPool, name: :op_defaults, create: create})

    # :size defaults to 5, so five connections exist eagerly at startup.
    assert created(counter) == 5

    s = OverflowPool.stats(:op_defaults)
    assert s.size == 5 and s.max_overflow == 0
    assert s.total == 5 and s.available == 5 and s.in_use == 0 and s.overflow == 0

    results = for _ <- 1..5, do: OverflowPool.checkout(:op_defaults, 100)
    assert Enum.all?(results, &match?({:ok, _}, &1))

    # :max_overflow defaults to 0, so the pool never grows past the base of 5.
    assert {:error, :timeout} = OverflowPool.checkout(:op_defaults, 50)
    assert created(counter) == 5

    s = OverflowPool.stats(:op_defaults)
    assert s.total == 5 and s.in_use == 5 and s.available == 0 and s.overflow == 0
  end

  # --- overflow creation ---------------------------------------------------

  test "creates overflow up to size + max_overflow, then times out" do
    start_supervised!({OverflowPool, name: :op_grow, size: 1, max_overflow: 1})
    assert {:ok, _c1} = OverflowPool.checkout(:op_grow, 100)
    assert {:ok, _c2} = OverflowPool.checkout(:op_grow, 100)

    s = OverflowPool.stats(:op_grow)
    assert s.total == 2 and s.overflow == 1

    assert {:error, :timeout} = OverflowPool.checkout(:op_grow, 50)
  end

  # --- zero timeout on a full pool -----------------------------------------

  test "checkout with timeout 0 on a full pool returns {:error, :timeout}" do
    start_supervised!({OverflowPool, name: :op_zero, size: 1, max_overflow: 0})

    # Exhaust the pool: base is in use and no overflow is allowed.
    assert {:ok, _c1} = OverflowPool.checkout(:op_zero, 100)

    # A timeout of 0 is a valid, non-blocking checkout that yields the
    # timeout result as a normal value when nothing is available.
    assert {:error, :timeout} = OverflowPool.checkout(:op_zero, 0)

    # The failed checkout borrowed nothing: the pool is unchanged.
    s = OverflowPool.stats(:op_zero)
    assert s.total == 1 and s.in_use == 1 and s.available == 0 and s.overflow == 0
  end

  test "checkout with timeout 0 hands out an available connection" do
    start_supervised!({OverflowPool, name: :op_zero_avail, size: 2, max_overflow: 0})

    # A zero timeout only bounds blocking; an available connection is still
    # handed out as a normal successful checkout.
    assert {:ok, c1} = OverflowPool.checkout(:op_zero_avail, 0)
    assert {:ok, c2} = OverflowPool.checkout(:op_zero_avail, 0)
    assert c1 != c2

    s = OverflowPool.stats(:op_zero_avail)
    assert s.total == 2 and s.in_use == 2 and s.available == 0 and s.overflow == 0
  end

  test "checkout with timeout 0 creates an overflow connection when the pool can grow" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {OverflowPool, name: :op_zero_grow, size: 1, max_overflow: 1, destroy: destroy}
    )

    assert {:ok, c1} = OverflowPool.checkout(:op_zero_grow, 100)

    # The base is fully in use but the pool is below size + max_overflow, so a
    # zero-timeout checkout lazily creates an overflow connection instead of
    # reporting a timeout.
    assert {:ok, c2} = OverflowPool.checkout(:op_zero_grow, 0)
    assert c1 != c2

    s = OverflowPool.stats(:op_zero_grow)
    assert s.total == 2 and s.in_use == 2 and s.available == 0 and s.overflow == 1

    # It is a genuine overflow connection: returning it with no waiter destroys it.
    assert :ok = OverflowPool.checkin(:op_zero_grow, c2)
    assert destroyed.() == [c2]
  end

  test "a zero-timeout checkout leaves no waiter behind for a later checkin" do
    start_supervised!({OverflowPool, name: :op_zero_no_waiter, size: 1, max_overflow: 0})

    assert {:ok, c1} = OverflowPool.checkout(:op_zero_no_waiter, 100)
    assert {:error, :timeout} = OverflowPool.checkout(:op_zero_no_waiter, 0)

    # That caller already has its timeout result, so the returned connection is
    # reused normally rather than handed to it.
    assert :ok = OverflowPool.checkin(:op_zero_no_waiter, c1)

    s = OverflowPool.stats(:op_zero_no_waiter)
    assert s.total == 1 and s.available == 1 and s.in_use == 0 and s.overflow == 0

    assert {:ok, ^c1} = OverflowPool.checkout(:op_zero_no_waiter, 0)
  end

  # --- ephemeral overflow --------------------------------------------------

  test "an overflow connection returned with no waiter is destroyed" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {OverflowPool, name: :op_eph, size: 1, max_overflow: 1, create: create, destroy: destroy}
    )

    assert {:ok, _c1} = OverflowPool.checkout(:op_eph, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_eph, 100)

    # c2 is overflow; returning it with c1 still in use and no waiter destroys it.
    assert :ok = OverflowPool.checkin(:op_eph, c2)
    assert destroyed.() == [c2]

    s = OverflowPool.stats(:op_eph)
    assert s.total == 1 and s.overflow == 0 and s.available == 0 and s.in_use == 1
  end

  test "a base connection returned with no waiter is kept available" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!({OverflowPool, name: :op_base, size: 2, max_overflow: 0, destroy: destroy})

    assert {:ok, c1} = OverflowPool.checkout(:op_base, 100)
    assert {:ok, _c2} = OverflowPool.checkout(:op_base, 100)
    assert :ok = OverflowPool.checkin(:op_base, c1)

    assert destroyed.() == []
    assert {:ok, ^c1} = OverflowPool.checkout(:op_base, 100)
  end

  test "an overflow connection handed to a waiter stays alive" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!({OverflowPool, name: :op_wait, size: 1, max_overflow: 1, destroy: destroy})

    {:ok, _c1} = OverflowPool.checkout(:op_wait, 100)
    {:ok, c2} = OverflowPool.checkout(:op_wait, 100)

    parent = self()

    # The waiter must stay alive after receiving its connection; otherwise the
    # pool's crash-reclamation would reclaim (and, as overflow, destroy) it.
    waiter =
      spawn(fn ->
        send(parent, {:result, OverflowPool.checkout(:op_wait, 1_000)})

        receive do
          :release -> :ok
        end
      end)

    Process.sleep(50)
    refute_received {:result, _}

    # A waiter exists, so returning the overflow connection hands it over alive.
    assert :ok = OverflowPool.checkin(:op_wait, c2)
    assert_receive {:result, {:ok, got}}, 1_000
    assert got == c2
    assert destroyed.() == []

    s = OverflowPool.stats(:op_wait)
    assert s.total == 2

    send(waiter, :release)
  end

  # --- waiter ordering -----------------------------------------------------

  test "blocked waiters are served in FIFO order, longest-waiting first" do
    start_supervised!({OverflowPool, name: :op_fifo, size: 2, max_overflow: 0})

    assert {:ok, c1} = OverflowPool.checkout(:op_fifo, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_fifo, 100)

    parent = self()

    spawn_waiter = fn tag ->
      spawn(fn ->
        send(parent, {:served, tag, OverflowPool.checkout(:op_fifo, 5_000)})

        receive do
          :release -> :ok
        end
      end)
    end

    # The pool is at size + max_overflow, so each waiter blocks rather than
    # being served; the first waiter is therefore enqueued before the second.
    first = spawn_waiter.(:first)
    refute_receive {:served, :first, _}, 100

    second = spawn_waiter.(:second)
    refute_receive {:served, :second, _}, 100

    # The returned connection goes directly to the longest-waiting caller.
    assert :ok = OverflowPool.checkin(:op_fifo, c1)
    assert_receive {:served, :first, {:ok, got1}}, 1_000
    assert got1 == c1

    # One connection serves exactly one caller: the later waiter still blocks.
    refute_receive {:served, :second, _}, 100

    assert :ok = OverflowPool.checkin(:op_fifo, c2)
    assert_receive {:served, :second, {:ok, got2}}, 1_000
    assert got2 == c2

    send(first, :release)
    send(second, :release)
  end

  # --- crash reclamation ---------------------------------------------------

  test "a crashed holder's connection is reclaimed" do
    start_supervised!({OverflowPool, name: :op_crash, size: 1, max_overflow: 0})
    {holder, {:ok, _conn}} = spawn_holder(:op_crash, 1_000)
    assert {:error, :timeout} = OverflowPool.checkout(:op_crash, 50)
    Process.exit(holder, :kill)
    assert {:ok, _reclaimed} = OverflowPool.checkout(:op_crash, 1_000)
  end

  test "distinct connections" do
    start_supervised!({OverflowPool, name: :op_distinct, size: 2, max_overflow: 0})
    assert {:ok, c1} = OverflowPool.checkout(:op_distinct, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_distinct, 100)
    assert c1 != c2
  end

  test "a crashed holder's overflow connection is destroyed on reclamation" do
    parent = self()
    destroy = fn conn -> send(parent, {:destroyed, conn}) end

    start_supervised!(
      {OverflowPool, name: :op_crash_ovf, size: 1, max_overflow: 1, destroy: destroy}
    )

    # The base connection stays in use here, so the holder's connection is overflow.
    assert {:ok, _c1} = OverflowPool.checkout(:op_crash_ovf, 100)
    {holder, {:ok, c2}} = spawn_holder(:op_crash_ovf, 1_000)
    assert OverflowPool.stats(:op_crash_ovf).overflow == 1

    Process.exit(holder, :kill)

    # No waiter exists, so the reclaimed overflow connection must be destroyed.
    assert_receive {:destroyed, ^c2}, 1_000

    s = OverflowPool.stats(:op_crash_ovf)
    assert s.total == 1 and s.overflow == 0 and s.in_use == 1 and s.available == 0
  end

  test "a crashed holder's connection goes to a blocked waiter and stays alive" do
    parent = self()
    destroy = fn conn -> send(parent, {:destroyed, conn}) end

    start_supervised!(
      {OverflowPool, name: :op_crash_wait, size: 1, max_overflow: 1, destroy: destroy}
    )

    assert {:ok, _c1} = OverflowPool.checkout(:op_crash_wait, 100)
    {holder, {:ok, c2}} = spawn_holder(:op_crash_wait, 1_000)

    waiter =
      spawn(fn ->
        send(parent, {:served, OverflowPool.checkout(:op_crash_wait, 5_000)})

        receive do
          :release -> :ok
        end
      end)

    # The pool is at size + max_overflow, so this caller is enqueued as a waiter.
    refute_receive {:served, _}, 100

    Process.exit(holder, :kill)

    # Demand still exists, so reclamation hands the connection over instead of destroying it.
    assert_receive {:served, {:ok, got}}, 1_000
    assert got == c2
    refute_receive {:destroyed, _}, 100
    assert OverflowPool.stats(:op_crash_wait).total == 2

    send(waiter, :release)
  end

  test "a waiter that already timed out is never served by a later checkin" do
    start_supervised!({OverflowPool, name: :op_stale, size: 1, max_overflow: 0})
    parent = self()

    assert {:ok, c1} = OverflowPool.checkout(:op_stale, 100)

    spawn(fn -> send(parent, {:done, OverflowPool.checkout(:op_stale, 100)}) end)
    assert_receive {:done, {:error, :timeout}}, 1_000

    # The waiter has retired: the returned connection must go back to the pool,
    # not to the caller that already got its timeout result.
    assert :ok = OverflowPool.checkin(:op_stale, c1)
    refute_receive {:done, _}, 200

    s = OverflowPool.stats(:op_stale)
    assert s.total == 1 and s.available == 1 and s.in_use == 0

    assert {:ok, ^c1} = OverflowPool.checkout(:op_stale, 100)
  end

  test "a checkin serves the next waiter when the longest-waiting one died" do
    start_supervised!({OverflowPool, name: :op_dead_waiter, size: 1, max_overflow: 0})
    parent = self()

    assert {:ok, c1} = OverflowPool.checkout(:op_dead_waiter, 100)

    spawn_waiter = fn tag ->
      spawn(fn ->
        send(parent, {:got, tag, OverflowPool.checkout(:op_dead_waiter, 5_000)})

        receive do
          :release -> :ok
        end
      end)
    end

    first = spawn_waiter.(:first)
    refute_receive {:got, :first, _}, 100
    second = spawn_waiter.(:second)
    refute_receive {:got, :second, _}, 100

    ref = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^ref, :process, ^first, :killed}, 1_000

    # The only live blocked caller must receive the connection.
    assert :ok = OverflowPool.checkin(:op_dead_waiter, c1)
    assert_receive {:got, :second, {:ok, got}}, 1_000
    assert got == c1

    send(second, :release)
  end

  test "the default connection factory hands out fresh distinct references" do
    start_supervised!({OverflowPool, name: :op_def_create, size: 1, max_overflow: 1})

    assert {:ok, c1} = OverflowPool.checkout(:op_def_create, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_def_create, 100)

    assert is_reference(c1) and is_reference(c2)
    assert c1 != c2
  end

  test "an overflow connection is dismissed cleanly without a :destroy option" do
    start_supervised!({OverflowPool, name: :op_no_destroy, size: 1, max_overflow: 1})

    assert {:ok, c1} = OverflowPool.checkout(:op_no_destroy, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_no_destroy, 100)

    # With the default no-op destroy the pool still shrinks back toward :size.
    assert :ok = OverflowPool.checkin(:op_no_destroy, c2)
    s = OverflowPool.stats(:op_no_destroy)
    assert s.total == 1 and s.overflow == 0 and s.in_use == 1 and s.available == 0

    assert :ok = OverflowPool.checkin(:op_no_destroy, c1)
    assert {:ok, ^c1} = OverflowPool.checkout(:op_no_destroy, 100)
  end
end
