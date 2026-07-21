# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ValidatingPool do
  @moduledoc """
  A `GenServer` connection pool that validates each connection immediately
  before handing it to a caller, discarding (and destroying) any that fail.
  """

  use GenServer

  defstruct available: [],
            in_use: %{},
            waiters: :queue.new(),
            total: 0,
            max: 10,
            min: 0,
            create: nil,
            validate: nil,
            destroy: nil

  # ── Public API ─────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec checkout(GenServer.server(), non_neg_integer()) :: {:ok, term()} | {:error, atom()}
  @doc "Checks out a connection from `name` within `timeout` ms. Returns `{:ok, conn}` or error."
  def checkout(name, timeout) when is_integer(timeout) and timeout >= 0 do
    GenServer.call(name, {:checkout, timeout}, :infinity)
  end

  def checkin(name, conn), do: GenServer.call(name, {:checkin, conn})

  def stats(name), do: GenServer.call(name, :stats)

  # ── Callbacks ──────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_size, 10)
    min = Keyword.get(opts, :min_size, 0)
    create = Keyword.get(opts, :create, fn -> make_ref() end)
    validate = Keyword.get(opts, :validate, fn _ -> true end)
    destroy = Keyword.get(opts, :destroy, fn _ -> :ok end)

    cond do
      not (is_integer(max) and max >= 0) ->
        {:stop, {:invalid_option, :max_size}}

      not (is_integer(min) and min >= 0) ->
        {:stop, {:invalid_option, :min_size}}

      min > max ->
        {:stop, {:invalid_option, :min_size_gt_max_size}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      not is_function(validate, 1) ->
        {:stop, {:invalid_option, :validate}}

      not is_function(destroy, 1) ->
        {:stop, {:invalid_option, :destroy}}

      true ->
        available = for _ <- 1..min//1, do: create.()

        {:ok,
         %__MODULE__{
           available: available,
           total: min,
           max: max,
           min: min,
           create: create,
           validate: validate,
           destroy: destroy
         }}
    end
  end

  @impl true
  def handle_call({:checkout, timeout}, from, state) do
    {pid, _tag} = from

    case take_valid(state) do
      {:ok, conn, state} ->
        {:reply, {:ok, conn}, assign(conn, pid, state)}

      {:none, state} ->
        cond do
          state.total < state.max ->
            conn = state.create.()
            {:reply, {:ok, conn}, assign(conn, pid, %{state | total: state.total + 1})}

          timeout == 0 ->
            {:reply, {:error, :timeout}, state}

          true ->
            mon = Process.monitor(pid)
            timer = Process.send_after(self(), {:waiter_timeout, mon}, timeout)
            waiter = %{from: from, pid: pid, mon: mon, timer: timer}
            {:noreply, %{state | waiters: :queue.in(waiter, state.waiters)}}
        end
    end
  end

  def handle_call({:checkin, conn}, _from, state) do
    case Map.pop(state.in_use, conn) do
      {{_pid, mon}, in_use} ->
        Process.demonitor(mon, [:flush])
        {:reply, :ok, deliver(conn, %{state | in_use: in_use})}

      {nil, _in_use} ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       available: length(state.available),
       in_use: map_size(state.in_use),
       total: state.total,
       max: state.max,
       min: state.min
     }, state}
  end

  @impl true
  def handle_info({:waiter_timeout, mon}, state) do
    case remove_waiter_by_mon(state.waiters, mon) do
      {:ok, waiter, rest} ->
        Process.demonitor(waiter.mon, [:flush])
        GenServer.reply(waiter.from, {:error, :timeout})
        {:noreply, %{state | waiters: rest}}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case find_conn_by_ref(state.in_use, ref) do
      {:ok, conn} ->
        in_use = Map.delete(state.in_use, conn)
        {:noreply, deliver(conn, %{state | in_use: in_use})}

      :error ->
        case remove_waiter_by_mon(state.waiters, ref) do
          {:ok, waiter, rest} ->
            _ = Process.cancel_timer(waiter.timer)
            {:noreply, %{state | waiters: rest}}

          :error ->
            {:noreply, state}
        end
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Helpers ────────────────────────────────────────────────────────────

  defp assign(conn, pid, state) do
    mon = Process.monitor(pid)
    %{state | in_use: Map.put(state.in_use, conn, {pid, mon})}
  end

  # Pull the first valid connection off the available list, discarding
  # (and destroying) any invalid ones encountered along the way.
  defp take_valid(state), do: do_take(state.available, state)

  defp do_take([], state), do: {:none, %{state | available: []}}

  defp do_take([conn | rest], state) do
    if state.validate.(conn) do
      {:ok, conn, %{state | available: rest}}
    else
      state.destroy.(conn)
      do_take(rest, %{state | total: state.total - 1})
    end
  end

  # Return a freed connection: hand to the longest-waiting caller (validating
  # first, replacing on failure) or place it back as available.
  defp deliver(conn, state) do
    case :queue.out(state.waiters) do
      {{:value, waiter}, rest} ->
        state = %{state | waiters: rest}
        _ = Process.cancel_timer(waiter.timer)

        if state.validate.(conn) do
          in_use = Map.put(state.in_use, conn, {waiter.pid, waiter.mon})
          GenServer.reply(waiter.from, {:ok, conn})
          %{state | in_use: in_use}
        else
          state.destroy.(conn)
          new_conn = state.create.()
          in_use = Map.put(state.in_use, new_conn, {waiter.pid, waiter.mon})
          GenServer.reply(waiter.from, {:ok, new_conn})
          # total unchanged: one destroyed, one created.
          %{state | in_use: in_use}
        end

      {:empty, _} ->
        %{state | available: [conn | state.available]}
    end
  end

  defp find_conn_by_ref(in_use, ref) do
    Enum.find_value(in_use, :error, fn
      {conn, {_pid, ^ref}} -> {:ok, conn}
      _ -> false
    end)
  end

  defp remove_waiter_by_mon(queue, mon) do
    list = :queue.to_list(queue)

    case Enum.split_with(list, fn w -> w.mon == mon end) do
      {[waiter], rest} -> {:ok, waiter, :queue.from_list(rest)}
      {[], _} -> :error
    end
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
