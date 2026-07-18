# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Health-Validated Connection Pool

Write me an Elixir module called `ValidatingPool` (a `GenServer`) that manages a pool of reusable connections **and validates every connection right before it hands it to a caller**. A "connection" is an opaque term produced by a factory function — a PID, a reference, or any value.

Unlike a plain pool, connections in a real system go stale (a socket closes, a DB session dies). This pool must never hand out a connection that fails validation: it checks each candidate first and silently discards the bad ones, replacing them so the caller always receives a healthy connection.

## Public API

- `ValidatingPool.start_link(opts)` — start and register the pool. Options:
  - `:name` — an atom to register the process under.
  - `:max_size` — the maximum number of connections alive at once. Defaults to `10`.
  - `:min_size` — connections created **eagerly** at startup. Defaults to `0`. Must be `<= max_size`.
  - `:create` — a zero-arity function returning a **new, distinct** connection. Defaults to `fn -> make_ref() end`.
  - `:validate` — a one-arity function `fn conn -> boolean end`. Defaults to `fn _ -> true end`. Called just before a connection is handed out.
  - `:destroy` — a one-arity function `fn conn -> :ok end` called when a connection is discarded. Defaults to a no-op.

- `ValidatingPool.checkout(name, timeout)` — borrow a **valid** connection.
  - Take connections from the available set one at a time; for each, call `:validate`. If it returns `false`, call `:destroy` on it, drop it from the pool (the total shrinks), and try the next one.
  - If a valid available connection is found, hand it out: `{:ok, conn}`.
  - If none are available (or all were discarded) and the pool has fewer than `max_size` connections alive, lazily create a fresh one (assumed valid) and hand it out.
  - If the pool is at `max_size` with nothing available, **block** the caller up to `timeout` ms for a connection to be returned; on success `{:ok, conn}`, otherwise `{:error, :timeout}`. A `timeout` of `0` returns `{:error, :timeout}` immediately.

- `ValidatingPool.checkin(name, conn)` — return a connection. Returns `:ok`. If a caller is blocked waiting, the returned connection is **validated before** being handed to the longest-waiting one; if it fails validation it is destroyed and a fresh connection is created for the waiter instead.

- `ValidatingPool.stats(name)` — return `%{available: a, in_use: u, total: t, max: max, min: min}` where `total == a + u`.

## Required behaviors

- **Validation on the way out.** No caller ever receives a connection that fails `:validate`. Invalid connections are destroyed (via `:destroy`) and do not count toward `total` afterward.
- **Lazy growth up to max**, distinct connections, and reuse of healthy returned connections.
- **Ownership monitoring / crash reclamation.** Monitor the checking-out process; if it dies while holding a connection, reclaim the connection (validating it before handing to any waiter).
- **Clean, server-side timeout.** A blocked `checkout` returns `{:error, :timeout}` as a normal value — implement the waiting/timeout logic in the server with a waiter queue and `Process.send_after` / `GenServer.reply`, not via `GenServer.call`'s own timeout.

Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.

## The module with `init` missing

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

  def init(opts) do
    # TODO
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

Give me only the complete implementation of `init` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
