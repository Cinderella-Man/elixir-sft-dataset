# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
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

  test "every invalid available connection is discarded before a fresh one is created" do
    {_counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_sweep, max_size: 3, create: create, validate: validate, destroy: destroy}
    )

    conns =
      for _ <- 1..3 do
        assert {:ok, c} = ValidatingPool.checkout(:vp_sweep, 100)
        c
      end

    Enum.each(conns, fn c -> assert :ok = ValidatingPool.checkin(:vp_sweep, c) end)
    Enum.each(conns, poison)

    # All three available connections are stale: each must be validated, destroyed
    # and dropped (total 3 -> 0) so that a fresh one can be created under max_size.
    assert {:ok, fresh} = ValidatingPool.checkout(:vp_sweep, 100)
    assert fresh == {:conn, 3}
    assert Enum.sort(destroyed_list.()) == Enum.sort(conns)

    s = ValidatingPool.stats(:vp_sweep)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end

  test "the longest-waiting blocked caller is served before a later one" do
    start_supervised!({ValidatingPool, name: :vp_fifo, max_size: 1})
    assert {:ok, c} = ValidatingPool.checkout(:vp_fifo, 100)

    parent = self()

    waiter = fn tag ->
      spawn(fn ->
        send(parent, {tag, ValidatingPool.checkout(:vp_fifo, 2_000)})

        # Stay alive: a dead waiter would trigger crash reclamation.
        receive do
          :release -> :ok
        end
      end)
    end

    waiter.(:first)
    refute_receive {:first, _}, 100
    waiter.(:second)
    refute_receive {:second, _}, 100

    assert :ok = ValidatingPool.checkin(:vp_fifo, c)
    assert_receive {:first, {:ok, ^c}}, 1_000
    refute_receive {:second, _}, 100
  end

  test "a zero timeout on an exhausted pool returns an error without blocking" do
    start_supervised!({ValidatingPool, name: :vp_zero, max_size: 1})
    assert {:ok, _c} = ValidatingPool.checkout(:vp_zero, 100)
    assert {:error, :timeout} = ValidatingPool.checkout(:vp_zero, 0)

    s = ValidatingPool.stats(:vp_zero)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end

  test "max_size defaults to ten and min_size defaults to zero" do
    {counter, create} = counting_create()
    start_supervised!({ValidatingPool, name: :vp_defaults, create: create})

    s = ValidatingPool.stats(:vp_defaults)
    assert s.max == 10 and s.min == 0
    assert s.total == 0 and s.available == 0 and s.in_use == 0
    assert created(counter) == 0

    for _ <- 1..10, do: assert({:ok, _} = ValidatingPool.checkout(:vp_defaults, 100))
    assert {:error, :timeout} = ValidatingPool.checkout(:vp_defaults, 0)
    assert ValidatingPool.stats(:vp_defaults).total == 10
  end

  test "the default create function hands out distinct references" do
    start_supervised!({ValidatingPool, name: :vp_defcreate, max_size: 2})
    assert {:ok, r1} = ValidatingPool.checkout(:vp_defcreate, 100)
    assert {:ok, r2} = ValidatingPool.checkout(:vp_defcreate, 100)
    assert is_reference(r1)
    assert is_reference(r2)
    assert r1 != r2
  end

  # --- validated handoff on checkin ----------------------------------------

  test "a healthy connection checked in is validated then handed to the waiter itself" do
    {counter, create} = counting_create()
    {:ok, checked} = Agent.start_link(fn -> [] end)
    {validate, destroy, _poison, destroyed_list} = validation_tools()

    recording_validate = fn conn ->
      Agent.update(checked, fn seen -> [conn | seen] end)
      validate.(conn)
    end

    start_supervised!(
      {ValidatingPool,
       name: :vp_ci_ok,
       max_size: 1,
       create: create,
       validate: recording_validate,
       destroy: destroy}
    )

    assert {:ok, c0} = ValidatingPool.checkout(:vp_ci_ok, 100)
    assert c0 == {:conn, 0}

    parent = self()

    spawn(fn ->
      send(parent, {:result, ValidatingPool.checkout(:vp_ci_ok, 2_000)})
      # Stay alive past the assertions: a dead waiter would trigger the
      # pool's crash reclamation and change the stats being asserted.
      receive do
        :release -> :ok
      end
    end)

    refute_receive {:result, _}, 100

    # The returned connection is validated before the blocked caller is served;
    # since it is healthy, that very connection is what the waiter receives.
    assert :ok = ValidatingPool.checkin(:vp_ci_ok, c0)
    assert_receive {:result, {:ok, ^c0}}, 1_000

    assert c0 in Agent.get(checked, & &1)
    assert destroyed_list.() == []
    assert created(counter) == 1

    s = ValidatingPool.stats(:vp_ci_ok)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end

  test "checkout skips stale connections and hands out an available healthy one" do
    {counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_mixed, max_size: 3, create: create, validate: validate, destroy: destroy}
    )

    conns =
      for _ <- 1..3 do
        assert {:ok, c} = ValidatingPool.checkout(:vp_mixed, 100)
        c
      end

    Enum.each(conns, fn c -> assert :ok = ValidatingPool.checkin(:vp_mixed, c) end)
    [c0, c1, c2] = conns
    poison.(c0)
    poison.(c1)

    # Two of the three available connections are stale: the caller must receive
    # the healthy one, and no new connection is created while one is available.
    assert {:ok, ^c2} = ValidatingPool.checkout(:vp_mixed, 100)
    assert created(counter) == 3

    # Only stale connections may be destroyed, and destroyed ones stop counting
    # toward the total.
    discarded = destroyed_list.()
    assert Enum.all?(discarded, fn c -> c in [c0, c1] end)

    s = ValidatingPool.stats(:vp_mixed)
    assert s.in_use == 1
    assert s.total == 3 - length(discarded)
    assert s.total == s.available + s.in_use
  end

  test "a waiter whose timeout elapses is not served by a later checkin" do
    start_supervised!({ValidatingPool, name: :vp_late, max_size: 1})
    assert {:ok, c} = ValidatingPool.checkout(:vp_late, 100)

    parent = self()

    # The server itself must expire this waiter: nothing here nudges it.
    spawn(fn -> send(parent, {:late, ValidatingPool.checkout(:vp_late, 25)}) end)
    assert_receive {:late, {:error, :timeout}}, 1_000

    # The connection returned afterwards belongs to nobody and becomes available
    # for the next checkout.
    assert :ok = ValidatingPool.checkin(:vp_late, c)

    s = ValidatingPool.stats(:vp_late)
    assert s.total == 1 and s.available == 1 and s.in_use == 0

    assert {:ok, ^c} = ValidatingPool.checkout(:vp_late, 100)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
