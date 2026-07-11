# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Pool do
  @moduledoc """
  A `GenServer` that manages a pool of reusable connections.

  A "connection" is an opaque term produced by a factory function and handed
  out to callers via `checkout/2`. Callers return connections with `checkin/2`.

  Features:

    * Lazy growth up to `:max_size`, with `:min_size` connections created
      eagerly at startup.
    * Distinct connections — a connection is never handed to two callers at once.
    * Ownership monitoring — if a process that checked out a connection dies,
      the pool reclaims the connection automatically.
    * Clean, server-side timeouts — a blocked `checkout/2` returns
      `{:error, :timeout}` as a normal value instead of crashing.
  """

  use GenServer

  # ── State ──────────────────────────────────────────────────────────────
  #
  #   available  - list of connections currently free
  #   in_use     - %{conn => {owner_pid, monitor_ref}}
  #   waiters    - :queue of %{from, pid, mon, timer} (FIFO, front = longest wait)
  #   total      - number of connections alive (available + in_use)
  #   max, min   - configured sizes
  #   create     - zero-arity factory function

  defstruct available: [],
            in_use: %{},
            waiters: :queue.new(),
            total: 0,
            max: 10,
            min: 0,
            create: nil

  # ── Public API ─────────────────────────────────────────────────────────

  @doc """
  Start and (optionally) register the pool process.

  Options:

    * `:name`     — atom to register the process under.
    * `:max_size` — maximum connections ever alive at once (default `10`).
    * `:min_size` — connections created eagerly at startup (default `0`).
    * `:create`   — zero-arity fun returning a new, distinct connection
      (default `fn -> make_ref() end`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Borrow a connection, blocking up to `timeout` milliseconds if the pool is at
  capacity. Returns `{:ok, conn}` or `{:error, :timeout}`.
  """
  def checkout(name, timeout) when is_integer(timeout) and timeout >= 0 do
    # We never rely on GenServer.call's own timeout — the server always replies
    # within `timeout` ms on its own, so we wait :infinity on the call itself.
    GenServer.call(name, {:checkout, timeout}, :infinity)
  end

  @doc """
  Return a previously checked-out connection to the pool. Always returns `:ok`.
  If a caller is blocked in `checkout/2`, the connection is handed directly to
  the longest-waiting one.
  """
  def checkin(name, conn) do
    GenServer.call(name, {:checkin, conn})
  end

  @doc """
  Return a map describing the current state of the pool:

      %{available: a, in_use: u, total: t, max: max, min: min}

  where `total == a + u`.
  """
  def stats(name) do
    GenServer.call(name, :stats)
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────

  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_size, 10)
    min = Keyword.get(opts, :min_size, 0)
    create = Keyword.get(opts, :create, fn -> make_ref() end)

    cond do
      not (is_integer(max) and max >= 0) ->
        {:stop, {:invalid_option, :max_size}}

      not (is_integer(min) and min >= 0) ->
        {:stop, {:invalid_option, :min_size}}

      min > max ->
        {:stop, {:invalid_option, :min_size_gt_max_size}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      true ->
        available = for _ <- 1..min//1, do: create.()

        state = %__MODULE__{
          available: available,
          in_use: %{},
          waiters: :queue.new(),
          total: min,
          max: max,
          min: min,
          create: create
        }

        {:ok, state}
    end
  end

  @impl true
  def handle_call({:checkout, timeout}, from, state) do
    {pid, _tag} = from

    cond do
      # 1. A connection is available — hand it out immediately.
      state.available != [] ->
        [conn | rest] = state.available
        state = assign(conn, pid, %{state | available: rest})
        {:reply, {:ok, conn}, state}

      # 2. Room to grow — lazily create a fresh connection.
      state.total < state.max ->
        conn = state.create.()
        state = assign(conn, pid, %{state | total: state.total + 1})
        {:reply, {:ok, conn}, state}

      # 3. At capacity, caller doesn't want to wait.
      timeout == 0 ->
        {:reply, {:error, :timeout}, state}

      # 4. At capacity — enqueue the caller as a waiter and reply later.
      true ->
        mon = Process.monitor(pid)
        timer = Process.send_after(self(), {:waiter_timeout, mon}, timeout)
        waiter = %{from: from, pid: pid, mon: mon, timer: timer}
        {:noreply, %{state | waiters: :queue.in(waiter, state.waiters)}}
    end
  end

  @impl true
  def handle_call({:checkin, conn}, _from, state) do
    case Map.pop(state.in_use, conn) do
      {{_pid, mon}, in_use} ->
        Process.demonitor(mon, [:flush])
        state = place_connection(conn, %{state | in_use: in_use})
        {:reply, :ok, state}

      {nil, _in_use} ->
        # Unknown / already-returned connection: place it as available anyway,
        # but only if it isn't already tracked, to avoid duplicates.
        state =
          if conn in state.available do
            state
          else
            place_connection(conn, state)
          end

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      available: length(state.available),
      in_use: map_size(state.in_use),
      total: state.total,
      max: state.max,
      min: state.min
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:waiter_timeout, mon}, state) do
    case remove_waiter_by_mon(state.waiters, mon) do
      {:ok, waiter, rest} ->
        Process.demonitor(waiter.mon, [:flush])
        GenServer.reply(waiter.from, {:error, :timeout})
        {:noreply, %{state | waiters: rest}}

      :error ->
        # Already served (and removed from the queue) before the timer fired.
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case find_conn_by_ref(state.in_use, ref) do
      {:ok, conn} ->
        # An owner died while holding a connection — reclaim it.
        in_use = Map.delete(state.in_use, conn)
        {:noreply, place_connection(conn, %{state | in_use: in_use})}

      :error ->
        # Maybe a waiting caller died before being served — drop it.
        case remove_waiter_by_mon(state.waiters, ref) do
          {:ok, waiter, rest} ->
            _ = Process.cancel_timer(waiter.timer)
            {:noreply, %{state | waiters: rest}}

          :error ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Helpers ──────────────────────────────────────────────────────────────

  # Record `conn` as in use by `pid`, monitoring the owner.
  defp assign(conn, pid, state) do
    mon = Process.monitor(pid)
    %{state | in_use: Map.put(state.in_use, conn, {pid, mon})}
  end

  # Return a freed connection either to the longest-waiting caller or to the
  # available pool.
  defp place_connection(conn, state) do
    case :queue.out(state.waiters) do
      {{:value, waiter}, rest} ->
        _ = Process.cancel_timer(waiter.timer)
        # The waiter's monitor becomes the ownership monitor for the connection.
        in_use = Map.put(state.in_use, conn, {waiter.pid, waiter.mon})
        GenServer.reply(waiter.from, {:ok, conn})
        %{state | waiters: rest, in_use: in_use}

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
    # TODO
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
```
