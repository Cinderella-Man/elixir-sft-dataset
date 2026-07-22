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
end
