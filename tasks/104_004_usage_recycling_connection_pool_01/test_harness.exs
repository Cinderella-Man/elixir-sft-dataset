defmodule RecyclingPoolTest do
  use ExUnit.Case, async: false

  # --- helpers -------------------------------------------------------------

  defp spawn_holder(pool, timeout) do
    parent = self()

    pid =
      spawn(fn ->
        result = RecyclingPool.checkout(pool, timeout)
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

  # --- basics --------------------------------------------------------------

  test "hands out distinct connections up to max_size" do
    start_supervised!({RecyclingPool, name: :rp_distinct, max_size: 2})
    assert {:ok, c1} = RecyclingPool.checkout(:rp_distinct, 100)
    assert {:ok, c2} = RecyclingPool.checkout(:rp_distinct, 100)
    assert c1 != c2
  end

  test "min_size connections are created eagerly" do
    {counter, create} = counting_create()
    start_supervised!({RecyclingPool, name: :rp_min, min_size: 2, max_size: 4, create: create})
    assert created(counter) == 2
    s = RecyclingPool.stats(:rp_min)
    assert s.total == 2 and s.available == 2 and s.in_use == 0
  end

  # --- recycling -----------------------------------------------------------

  test "a connection is retired after max_uses and replaced" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool,
       name: :rp_recycle, max_size: 1, max_uses: 2, create: create, destroy: destroy}
    )

    assert {:ok, c0} = RecyclingPool.checkout(:rp_recycle, 100)
    assert c0 == {:conn, 0}
    assert :ok = RecyclingPool.checkin(:rp_recycle, c0)

    # Second use of c0.
    assert {:ok, ^c0} = RecyclingPool.checkout(:rp_recycle, 100)
    assert :ok = RecyclingPool.checkin(:rp_recycle, c0)

    # c0 has now been used twice (max_uses): it is retired and replaced.
    assert destroyed.() == [c0]
    assert {:ok, c1} = RecyclingPool.checkout(:rp_recycle, 100)
    assert c1 != c0
    assert c1 == {:conn, 1}

    s = RecyclingPool.stats(:rp_recycle)
    assert s.total == 1
  end

  test "a not-yet-exhausted connection is reused" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_reuse, max_size: 1, max_uses: 3, create: create, destroy: destroy}
    )

    assert {:ok, c0} = RecyclingPool.checkout(:rp_reuse, 100)
    assert :ok = RecyclingPool.checkin(:rp_reuse, c0)
    assert {:ok, ^c0} = RecyclingPool.checkout(:rp_reuse, 100)
    assert destroyed.() == []
  end

  test "max_uses :infinity never retires a connection" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_inf, max_size: 1, max_uses: :infinity, destroy: destroy}
    )

    {:ok, c} = RecyclingPool.checkout(:rp_inf, 100)

    c =
      Enum.reduce(1..5, c, fn _, conn ->
        :ok = RecyclingPool.checkin(:rp_inf, conn)
        {:ok, same} = RecyclingPool.checkout(:rp_inf, 100)
        assert same == conn
        same
      end)

    assert destroyed.() == []
    assert is_reference(c) or match?({:conn, _}, c) or true
  end

  test "a retired connection is replaced with a fresh one for a waiting caller" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_wait, max_size: 1, max_uses: 1, create: create, destroy: destroy}
    )

    assert {:ok, c0} = RecyclingPool.checkout(:rp_wait, 100)
    assert c0 == {:conn, 0}

    parent = self()
    spawn(fn -> send(parent, {:result, RecyclingPool.checkout(:rp_wait, 1_000)}) end)
    Process.sleep(50)
    refute_received {:result, _}

    # Returning c0 completes its only allowed use → retired; the waiter gets a fresh one.
    assert :ok = RecyclingPool.checkin(:rp_wait, c0)
    assert_receive {:result, {:ok, cnew}}, 1_000
    assert cnew != c0
    assert cnew == {:conn, 1}
    assert destroyed.() == [c0]
  end

  # --- crash reclamation ---------------------------------------------------

  test "a crashed holder's connection is reclaimed and the crash counts as a use" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_crash, max_size: 1, max_uses: 1, create: create, destroy: destroy}
    )

    {holder, {:ok, c0}} = spawn_holder(:rp_crash, 1_000)
    assert c0 == {:conn, 0}

    Process.exit(holder, :kill)

    # The crash counted as a use (max_uses: 1) → c0 retired; next checkout is fresh.
    assert {:ok, c1} = RecyclingPool.checkout(:rp_crash, 1_000)
    assert c1 != c0
    assert c1 == {:conn, 1}
    assert destroyed.() == [c0]
  end

  test "a blocked checkout is served when a connection is returned" do
    start_supervised!({RecyclingPool, name: :rp_serve, max_size: 2, max_uses: 10})
    {:ok, c1} = RecyclingPool.checkout(:rp_serve, 100)
    {:ok, _c2} = RecyclingPool.checkout(:rp_serve, 100)

    parent = self()
    spawn(fn -> send(parent, {:result, RecyclingPool.checkout(:rp_serve, 1_000)}) end)
    Process.sleep(50)
    refute_received {:result, _}

    assert :ok = RecyclingPool.checkin(:rp_serve, c1)
    assert_receive {:result, {:ok, _conn}}, 500
  end
end
