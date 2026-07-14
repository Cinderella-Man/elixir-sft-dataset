defmodule ValidatingPoolTest do
  use ExUnit.Case, async: false

  # --- helpers -------------------------------------------------------------

  defp spawn_holder(pool, timeout) do
    parent = self()

    pid =
      spawn(fn ->
        result = ValidatingPool.checkout(pool, timeout)
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

  # validate/destroy tooling backed by agents
  defp validation_tools do
    {:ok, bad} = Agent.start_link(fn -> MapSet.new() end)
    {:ok, destroyed} = Agent.start_link(fn -> [] end)

    validate = fn conn -> not MapSet.member?(Agent.get(bad, & &1), conn) end
    destroy = fn conn -> Agent.update(destroyed, fn d -> [conn | d] end) end
    poison = fn conn -> Agent.update(bad, fn s -> MapSet.put(s, conn) end) end
    destroyed_list = fn -> Enum.reverse(Agent.get(destroyed, & &1)) end

    {validate, destroy, poison, destroyed_list}
  end

  # --- basics --------------------------------------------------------------

  test "hands out distinct connections up to max_size" do
    start_supervised!({ValidatingPool, name: :vp_distinct, max_size: 2})
    assert {:ok, c1} = ValidatingPool.checkout(:vp_distinct, 100)
    assert {:ok, c2} = ValidatingPool.checkout(:vp_distinct, 100)
    assert c1 != c2
  end

  test "exhaustion times out cleanly, checkin frees a slot" do
    start_supervised!({ValidatingPool, name: :vp_basic, max_size: 1})
    assert {:ok, c} = ValidatingPool.checkout(:vp_basic, 100)
    assert {:error, :timeout} = ValidatingPool.checkout(:vp_basic, 20)
    assert :ok = ValidatingPool.checkin(:vp_basic, c)
    assert {:ok, ^c} = ValidatingPool.checkout(:vp_basic, 100)
  end

  test "min_size connections are created eagerly" do
    {counter, create} = counting_create()
    start_supervised!({ValidatingPool, name: :vp_min, min_size: 2, max_size: 4, create: create})
    assert created(counter) == 2
    s = ValidatingPool.stats(:vp_min)
    assert s.total == 2 and s.available == 2 and s.in_use == 0
  end

  # --- validation ----------------------------------------------------------

  test "an invalid connection is discarded and replaced on checkout" do
    {_counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_val, max_size: 1, create: create, validate: validate, destroy: destroy}
    )

    assert {:ok, c0} = ValidatingPool.checkout(:vp_val, 100)
    assert c0 == {:conn, 0}
    assert :ok = ValidatingPool.checkin(:vp_val, c0)

    # Poison the returned connection: the next checkout must not hand it out.
    poison.(c0)
    assert {:ok, c1} = ValidatingPool.checkout(:vp_val, 100)
    assert c1 != c0
    assert c1 == {:conn, 1}
    assert destroyed_list.() == [c0]

    s = ValidatingPool.stats(:vp_val)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end

  test "a valid connection is reused (validate not a discard)" do
    {_counter, create} = counting_create()
    {validate, destroy, _poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_reuse, max_size: 1, create: create, validate: validate, destroy: destroy}
    )

    assert {:ok, c0} = ValidatingPool.checkout(:vp_reuse, 100)
    assert :ok = ValidatingPool.checkin(:vp_reuse, c0)
    assert {:ok, ^c0} = ValidatingPool.checkout(:vp_reuse, 100)
    assert destroyed_list.() == []
  end

  # --- waiter served -------------------------------------------------------

  test "a blocked checkout is served when a valid connection is returned" do
    start_supervised!({ValidatingPool, name: :vp_wait, max_size: 2})
    {:ok, c1} = ValidatingPool.checkout(:vp_wait, 100)
    {:ok, _c2} = ValidatingPool.checkout(:vp_wait, 100)

    parent = self()

    spawn(fn ->
      send(parent, {:result, ValidatingPool.checkout(:vp_wait, 1_000)})
      # Stay alive past the assertions: a dead waiter would trigger the
      # pool's crash reclamation and change the stats being asserted.
      receive do
        :release -> :ok
      end
    end)

    Process.sleep(50)
    refute_received {:result, _}

    assert :ok = ValidatingPool.checkin(:vp_wait, c1)
    assert_receive {:result, {:ok, _conn}}, 500
  end

  test "a connection checked in stale is validated before reaching the waiter" do
    {_counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_ci_val, max_size: 1, create: create, validate: validate, destroy: destroy}
    )

    assert {:ok, c0} = ValidatingPool.checkout(:vp_ci_val, 100)
    assert c0 == {:conn, 0}

    parent = self()

    spawn(fn ->
      send(parent, {:result, ValidatingPool.checkout(:vp_ci_val, 1_000)})
      # Stay alive past the assertions: a dead waiter would trigger the
      # pool's crash reclamation and change the stats being asserted.
      receive do
        :release -> :ok
      end
    end)

    refute_receive {:result, _}, 100

    # The held connection goes stale before it is returned: checking it in must
    # not hand it to the blocked caller; a fresh connection is created instead.
    poison.(c0)
    assert :ok = ValidatingPool.checkin(:vp_ci_val, c0)

    assert_receive {:result, {:ok, cnew}}, 1_000
    assert cnew != c0
    assert cnew == {:conn, 1}
    assert destroyed_list.() == [c0]

    s = ValidatingPool.stats(:vp_ci_val)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end

  # --- crash reclamation ---------------------------------------------------

  test "a crashed holder's connection is reclaimed" do
    start_supervised!({ValidatingPool, name: :vp_crash, min_size: 0, max_size: 1})
    {holder, {:ok, _conn}} = spawn_holder(:vp_crash, 1_000)
    assert {:error, :timeout} = ValidatingPool.checkout(:vp_crash, 50)
    Process.exit(holder, :kill)
    assert {:ok, _reclaimed} = ValidatingPool.checkout(:vp_crash, 1_000)
  end

  test "a reclaimed invalid connection is replaced for a waiting caller" do
    {_counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_crash_val, max_size: 1, create: create, validate: validate, destroy: destroy}
    )

    {holder, {:ok, c0}} = spawn_holder(:vp_crash_val, 1_000)
    assert c0 == {:conn, 0}

    parent = self()

    spawn(fn ->
      send(parent, {:result, ValidatingPool.checkout(:vp_crash_val, 1_000)})
      # Stay alive past the assertions: a dead waiter would trigger the
      # pool's crash reclamation and change the stats being asserted.
      receive do
        :release -> :ok
      end
    end)

    Process.sleep(50)
    refute_received {:result, _}

    poison.(c0)
    Process.exit(holder, :kill)

    assert_receive {:result, {:ok, cnew}}, 1_000
    assert cnew != c0
    assert cnew == {:conn, 1}
    assert destroyed_list.() == [c0]
  end
end
