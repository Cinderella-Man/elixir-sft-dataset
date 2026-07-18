# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Overflow Connection Pool

Write me an Elixir module called `OverflowPool` (a `GenServer`) that manages a pool of reusable connections with **poolboy-style overflow semantics**. A "connection" is an opaque term produced by a factory function — a PID, a reference, or any value.

The pool keeps a fixed base of persistent connections but can create a bounded number of **temporary overflow connections** under load. When an overflow connection is no longer needed, it is destroyed rather than kept, so the pool shrinks back to its base size during quiet periods.

## Public API

- `OverflowPool.start_link(opts)` — start and register the pool. Options:
  - `:name` — an atom to register the process under.
  - `:size` — the number of **persistent** connections, created **eagerly** at startup. Defaults to `5`.
  - `:max_overflow` — the maximum number of extra temporary connections allowed beyond `:size`. Defaults to `0`. The pool never has more than `size + max_overflow` connections alive at once.
  - `:create` — a zero-arity function returning a **new, distinct** connection. Defaults to `fn -> make_ref() end`.
  - `:destroy` — a one-arity function `fn conn -> :ok end` called when an overflow connection is dismissed. Defaults to a no-op.

- `OverflowPool.checkout(name, timeout)` — borrow a connection.
  - If a connection is available, hand it out immediately: `{:ok, conn}`.
  - Otherwise, if the pool has fewer than `size + max_overflow` connections alive, lazily create one and hand it out (this is an overflow connection when the base is already fully in use).
  - If the pool is at `size + max_overflow`, **block** the caller up to `timeout` ms; on success `{:ok, conn}`, otherwise `{:error, :timeout}`. A `timeout` of `0` returns `{:error, :timeout}` immediately.

- `OverflowPool.checkin(name, conn)` — return a connection. Returns `:ok`.
  - If a caller is blocked waiting, hand the connection **directly** to the longest-waiting one (the connection stays alive regardless of overflow — demand still exists).
  - Otherwise, if the pool currently has **more than `size`** connections alive, this connection is an overflow connection: **destroy** it (via `:destroy`) and let the total shrink back toward `size`. If the pool is at or below `size`, keep the connection available for reuse.

- `OverflowPool.stats(name)` — return `%{available: a, in_use: u, total: t, size: size, max_overflow: max_overflow, overflow: o}` where `a` and `u` are the counts of available and in-use connections, `total == a + u`, and `overflow == max(0, total - size)`.

## Required behaviors

- **Eager base, lazy overflow.** Exactly `:size` connections exist at startup; overflow connections are created only on demand and never exceed `max_size = size + max_overflow` total.
- **Overflow connections are ephemeral.** A returned overflow connection with no waiter is destroyed, not pooled — but if a caller is waiting, it is handed over and stays alive.
- **Distinct connections.** No connection is handed to two callers at once.
- **Ownership monitoring / crash reclamation.** Monitor the checking-out process; if it dies while holding a connection, reclaim it (handing to a waiter, or destroying if it is now overflow). If instead it dies while still blocked in the waiter queue, drop it from the queue so it is never served — a later checkin then goes to the next still-live waiter.
- **Clean, server-side timeout.** A blocked `checkout` returns `{:error, :timeout}` as a normal value, and a waiter that has already timed out is retired: a later checkin must not hand it a connection but instead reuse the connection normally. Implement waiting/timeout in the server with a waiter queue and `Process.send_after` / `GenServer.reply`, not via `GenServer.call`'s own timeout.

Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.

## The buggy module

```elixir
defmodule OverflowPool do
  @moduledoc """
  A `GenServer` connection pool with poolboy-style overflow: a fixed base of
  persistent connections plus a bounded number of temporary overflow
  connections that are destroyed when returned and no longer needed.
  """

  use GenServer

  defstruct available: [],
            in_use: %{},
            waiters: :queue.new(),
            total: 0,
            size: 5,
            max_overflow: 0,
            create: nil,
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
    size = Keyword.get(opts, :size, 5)
    max_overflow = Keyword.get(opts, :max_overflow, 0)
    create = Keyword.get(opts, :create, fn -> make_ref() end)
    destroy = Keyword.get(opts, :destroy, fn _ -> :ok end)

    cond do
      not (is_integer(size) and size >= 0) ->
        {:stop, {:invalid_option, :size}}

      not (is_integer(max_overflow) and max_overflow >= 0) ->
        {:stop, {:invalid_option, :max_overflow}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      not is_function(destroy, 1) ->
        {:stop, {:invalid_option, :destroy}}

      true ->
        available = for _ <- 1..size//1, do: create.()

        {:ok,
         %__MODULE__{
           available: available,
           total: size,
           size: size,
           max_overflow: max_overflow,
           create: create,
           destroy: destroy
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

      state.total < state.size + state.max_overflow ->
        conn = state.create.()
        {:reply, {:ok, conn}, assign(conn, pid, %{state | total: state.total + 1})}

      timeout == 0 ->
        {:reply, {:error, :timeout}, state}

      false ->
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
       size: state.size,
       max_overflow: state.max_overflow,
       overflow: max(0, state.total - state.size)
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

  # Return a freed connection: hand to a waiter (kept alive), else destroy it
  # if it is an overflow connection, else keep it available.
  defp release(conn, state) do
    case :queue.out(state.waiters) do
      {{:value, waiter}, rest} ->
        _ = Process.cancel_timer(waiter.timer)
        in_use = Map.put(state.in_use, conn, {waiter.pid, waiter.mon})
        GenServer.reply(waiter.from, {:ok, conn})
        %{state | waiters: rest, in_use: in_use}

      {:empty, _} ->
        if state.total > state.size do
          state.destroy.(conn)
          %{state | total: state.total - 1}
        else
          %{state | available: [conn | state.available]}
        end
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

## Failing test report

```
3 of 7 test(s) failed:

  * test creates overflow up to size + max_overflow, then times out
      :exit: {{:cond_clause, [{OverflowPool, :handle_call, 3, [file: ~c".gen_staging/bugfix_104_003_overflow_connection_pool_03_mutant.ex", line: 90]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}, {GenServer, :call, [:op_grow, {:checkout, 50}, :infinity]}}

  * test an overflow connection handed to a waiter stays alive
      
      
      Assertion failed, no matching message after 1000ms
           The process mailbox is empty.
      code: assert_receive {:result, {:ok, got}}
      

  * test a crashed holder's connection is reclaimed
      :exit: {{:cond_clause, [{OverflowPool, :handle_call, 3, [file: ~c".gen_staging/bugfix_104_003_overflow_connection_pool_03_mutant.ex", line: 90]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}, {GenServer, :call, [:op_crash, {:checkout, 50}, :infinity]}}
```
