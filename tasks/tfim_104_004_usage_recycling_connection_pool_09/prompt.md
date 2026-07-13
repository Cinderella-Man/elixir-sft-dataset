# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule RecyclingPool do
  @moduledoc """
  A `GenServer` connection pool that retires each connection after a configured
  number of uses (`:max_uses`), destroying it and lazily creating a replacement.
  """

  use GenServer

  defstruct available: [],
            in_use: %{},
            waiters: :queue.new(),
            total: 0,
            max: 10,
            min: 0,
            max_uses: :infinity,
            create: nil,
            destroy: nil,
            uses: %{}

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
    max_uses = Keyword.get(opts, :max_uses, :infinity)
    create = Keyword.get(opts, :create, fn -> make_ref() end)
    destroy = Keyword.get(opts, :destroy, fn _ -> :ok end)

    cond do
      not (is_integer(max) and max >= 0) ->
        {:stop, {:invalid_option, :max_size}}

      not (is_integer(min) and min >= 0) ->
        {:stop, {:invalid_option, :min_size}}

      min > max ->
        {:stop, {:invalid_option, :min_size_gt_max_size}}

      not (max_uses == :infinity or (is_integer(max_uses) and max_uses > 0)) ->
        {:stop, {:invalid_option, :max_uses}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      not is_function(destroy, 1) ->
        {:stop, {:invalid_option, :destroy}}

      true ->
        available = for _ <- 1..min//1, do: create.()
        uses = Map.new(available, fn c -> {c, 0} end)

        {:ok,
         %__MODULE__{
           available: available,
           total: min,
           max: max,
           min: min,
           max_uses: max_uses,
           create: create,
           destroy: destroy,
           uses: uses
         }}
    end
  end

  @impl true
  def handle_call({:checkout, timeout}, from, state) do
    {pid, _tag} = from

    cond do
      state.available != [] ->
        [conn | rest] = state.available
        {:reply, {:ok, conn}, assign(conn, pid, %{state | available: rest})}

      state.total < state.max ->
        conn = state.create.()
        state = %{state | total: state.total + 1, uses: Map.put(state.uses, conn, 0)}
        {:reply, {:ok, conn}, assign(conn, pid, state)}

      timeout == 0 ->
        {:reply, {:error, :timeout}, state}

      true ->
        mon = Process.monitor(pid)
        timer = Process.send_after(self(), {:waiter_timeout, mon}, timeout)
        waiter = %{from: from, pid: pid, mon: mon, timer: timer}
        {:noreply, %{state | waiters: :queue.in(waiter, state.waiters)}}
    end
  end

  def handle_call({:checkin, conn}, _from, state) do
    case Map.pop(state.in_use, conn) do
      {{_pid, mon}, in_use} ->
        Process.demonitor(mon, [:flush])
        {:reply, :ok, release(conn, %{state | in_use: in_use})}

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
       min: state.min,
       max_uses: state.max_uses
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
        {:noreply, release(conn, %{state | in_use: in_use})}

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

  # A completed use: bump the count, then retire-or-return the connection.
  defp release(conn, state) do
    count = Map.get(state.uses, conn, 0) + 1
    state = %{state | uses: Map.delete(state.uses, conn)}

    if retire?(count, state.max_uses) do
      state.destroy.(conn)
      state = %{state | total: state.total - 1}

      case :queue.out(state.waiters) do
        {{:value, waiter}, rest} ->
          _ = Process.cancel_timer(waiter.timer)
          new = state.create.()
          in_use = Map.put(state.in_use, new, {waiter.pid, waiter.mon})
          GenServer.reply(waiter.from, {:ok, new})

          %{
            state
            | waiters: rest,
              in_use: in_use,
              total: state.total + 1,
              uses: Map.put(state.uses, new, 0)
          }

        {:empty, _} ->
          state
      end
    else
      case :queue.out(state.waiters) do
        {{:value, waiter}, rest} ->
          _ = Process.cancel_timer(waiter.timer)
          in_use = Map.put(state.in_use, conn, {waiter.pid, waiter.mon})
          GenServer.reply(waiter.from, {:ok, conn})
          %{state | waiters: rest, in_use: in_use, uses: Map.put(state.uses, conn, count)}

        {:empty, _} ->
          %{state | available: [conn | state.available], uses: Map.put(state.uses, conn, count)}
      end
    end
  end

  defp retire?(_count, :infinity), do: false
  defp retire?(count, max_uses) when is_integer(max_uses), do: count >= max_uses

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

    assert_receive {:checked_out, ^pid, result}, 5_000
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
    assert {:ok, c1} = RecyclingPool.checkout(:rp_distinct, 2_000)
    assert {:ok, c2} = RecyclingPool.checkout(:rp_distinct, 2_000)
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

    assert {:ok, c0} = RecyclingPool.checkout(:rp_recycle, 2_000)
    assert c0 == {:conn, 0}
    assert :ok = RecyclingPool.checkin(:rp_recycle, c0)

    # Second use of c0.
    assert {:ok, ^c0} = RecyclingPool.checkout(:rp_recycle, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_recycle, c0)

    # c0 has now been used twice (max_uses): it is retired and replaced.
    assert destroyed.() == [c0]
    assert {:ok, c1} = RecyclingPool.checkout(:rp_recycle, 2_000)
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

    assert {:ok, c0} = RecyclingPool.checkout(:rp_reuse, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_reuse, c0)
    assert {:ok, ^c0} = RecyclingPool.checkout(:rp_reuse, 2_000)
    assert destroyed.() == []
  end

  test "max_uses :infinity never retires a connection" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_inf, max_size: 1, max_uses: :infinity, destroy: destroy}
    )

    {:ok, c} = RecyclingPool.checkout(:rp_inf, 2_000)

    c =
      Enum.reduce(1..5, c, fn _, conn ->
        :ok = RecyclingPool.checkin(:rp_inf, conn)
        {:ok, same} = RecyclingPool.checkout(:rp_inf, 2_000)
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

    assert {:ok, c0} = RecyclingPool.checkout(:rp_wait, 2_000)
    assert c0 == {:conn, 0}

    parent = self()
    spawn(fn -> send(parent, {:result, RecyclingPool.checkout(:rp_wait, 5_000)}) end)
    Process.sleep(50)
    refute_received {:result, _}

    # Returning c0 completes its only allowed use → retired; the waiter gets a fresh one.
    assert :ok = RecyclingPool.checkin(:rp_wait, c0)
    assert_receive {:result, {:ok, cnew}}, 5_000
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

    {holder, {:ok, c0}} = spawn_holder(:rp_crash, 5_000)
    assert c0 == {:conn, 0}

    Process.exit(holder, :kill)

    # The crash counted as a use (max_uses: 1) → c0 retired; next checkout is fresh.
    assert {:ok, c1} = RecyclingPool.checkout(:rp_crash, 5_000)
    assert c1 != c0
    assert c1 == {:conn, 1}
    assert destroyed.() == [c0]
  end

  test "a blocked checkout is served when a connection is returned" do
    # TODO
  end

  # --- defaults & option validation ----------------------------------------

  test "defaults are max_size 10, min_size 0, max_uses :infinity and an empty pool" do
    start_supervised!({RecyclingPool, name: :rp_defaults})

    s = RecyclingPool.stats(:rp_defaults)
    assert s.max == 10
    assert s.min == 0
    assert s.max_uses == :infinity
    assert s.total == 0
    assert s.available == 0
    assert s.in_use == 0
  end

  test "min_size equal to max_size is accepted and pre-fills the pool" do
    start_supervised!({RecyclingPool, name: :rp_min_eq_max, min_size: 2, max_size: 2})

    s = RecyclingPool.stats(:rp_min_eq_max)
    assert s.min == 2
    assert s.max == 2
    assert s.total == 2
    assert s.available == 2
    assert s.in_use == 0
  end

  test "min_size greater than max_size and a non-positive max_uses are rejected" do
    Process.flag(:trap_exit, true)

    assert {:error, _} = RecyclingPool.start_link(min_size: 3, max_size: 2)
    assert {:error, _} = RecyclingPool.start_link(max_uses: 0)
  end

  # --- timeout semantics ---------------------------------------------------

  test "timeout 0 is accepted: it serves when possible and errors when exhausted" do
    start_supervised!({RecyclingPool, name: :rp_zero, max_size: 1})

    # A zero timeout still creates/serves a connection when one can be had.
    assert {:ok, c} = RecyclingPool.checkout(:rp_zero, 0)
    # At max_size with nothing available, a zero timeout errors immediately.
    assert {:error, :timeout} = RecyclingPool.checkout(:rp_zero, 0)

    assert :ok = RecyclingPool.checkin(:rp_zero, c)
    assert {:ok, ^c} = RecyclingPool.checkout(:rp_zero, 0)
  end

  test "a blocked checkout times out server-side and leaves the pool usable" do
    start_supervised!({RecyclingPool, name: :rp_block_timeout, max_size: 1})

    assert {:ok, c} = RecyclingPool.checkout(:rp_block_timeout, 2_000)
    assert {:error, :timeout} = RecyclingPool.checkout(:rp_block_timeout, 100)

    s = RecyclingPool.stats(:rp_block_timeout)
    assert s.total == 1
    assert s.in_use == 1
    assert s.available == 0

    # The timed-out waiter is gone: a returned connection becomes available again.
    assert :ok = RecyclingPool.checkin(:rp_block_timeout, c)
    assert %{available: 1, in_use: 0} = RecyclingPool.stats(:rp_block_timeout)
    assert {:ok, ^c} = RecyclingPool.checkout(:rp_block_timeout, 0)
  end

  test "a waiter that dies while blocked is not handed a connection" do
    start_supervised!({RecyclingPool, name: :rp_dead_waiter, max_size: 1})

    assert {:ok, c} = RecyclingPool.checkout(:rp_dead_waiter, 2_000)

    waiter = spawn(fn -> RecyclingPool.checkout(:rp_dead_waiter, 5_000) end)
    Process.sleep(50)
    Process.exit(waiter, :kill)
    Process.sleep(50)

    assert :ok = RecyclingPool.checkin(:rp_dead_waiter, c)

    s = RecyclingPool.stats(:rp_dead_waiter)
    assert s.available == 1
    assert s.in_use == 0
    assert s.total == 1

    assert {:ok, ^c} = RecyclingPool.checkout(:rp_dead_waiter, 0)
  end

  # --- use accounting ------------------------------------------------------

  test "an eagerly created connection starts at zero uses" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool,
       name: :rp_eager_uses, min_size: 1, max_size: 1, max_uses: 2, destroy: destroy}
    )

    assert {:ok, c} = RecyclingPool.checkout(:rp_eager_uses, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_eager_uses, c)
    # Only one use so far: not retired, and reused.
    assert destroyed.() == []
    assert {:ok, ^c} = RecyclingPool.checkout(:rp_eager_uses, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_eager_uses, c)
    # Second use reaches max_uses: retired now.
    assert destroyed.() == [c]
  end

  test "a lazily created connection starts at zero uses" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_lazy_uses, max_size: 1, max_uses: 2, destroy: destroy}
    )

    assert {:ok, c} = RecyclingPool.checkout(:rp_lazy_uses, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_lazy_uses, c)
    assert destroyed.() == []
    assert {:ok, ^c} = RecyclingPool.checkout(:rp_lazy_uses, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_lazy_uses, c)
    assert destroyed.() == [c]
  end

  test "replacing a retired connection for a waiter keeps total at max_size" do
    {_counter, create} = counting_create()

    start_supervised!(
      {RecyclingPool, name: :rp_repl_total, max_size: 1, max_uses: 1, create: create}
    )

    assert {:ok, c0} = RecyclingPool.checkout(:rp_repl_total, 2_000)
    parent = self()

    holder =
      spawn(fn ->
        send(parent, {:result, RecyclingPool.checkout(:rp_repl_total, 5_000)})

        receive do
          :release -> :ok
        end
      end)

    Process.sleep(50)
    assert :ok = RecyclingPool.checkin(:rp_repl_total, c0)
    assert_receive {:result, {:ok, cnew}}, 5_000
    assert cnew != c0

    s = RecyclingPool.stats(:rp_repl_total)
    assert s.total == 1
    assert s.in_use == 1
    assert s.available == 0

    send(holder, :release)
  end
end
```
