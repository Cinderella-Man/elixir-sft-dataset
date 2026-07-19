# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `assign` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Usage-Recycling Connection Pool

Write me an Elixir module called `RecyclingPool` (a `GenServer`) that manages a pool of reusable connections and **retires each connection after it has been used a fixed number of times**, replacing it with a fresh one. A "connection" is an opaque term produced by a factory function — a PID, a reference, or any value.

Long-lived connections accumulate state and eventually should be recycled. This pool caps how many times any single connection may be checked out; once a connection reaches its limit, the pool destroys it (rather than returning it to the available set) and lazily creates a replacement on the next demand.

## Public API

- `RecyclingPool.start_link(opts)` — start and register the pool. Options:
  - `:name` — an atom to register the process under.
  - `:max_size` — the maximum number of connections alive at once. Defaults to `10`.
  - `:min_size` — connections created **eagerly** at startup. Defaults to `0`. Must be `<= max_size`.
  - `:max_uses` — a positive integer, the number of completed uses after which a connection is retired, or `:infinity` for never. Defaults to `:infinity`. One checkout-then-return (or a crash while holding) counts as one use.
  - `:create` — a zero-arity function returning a **new, distinct** connection. Defaults to `fn -> make_ref() end`.
  - `:destroy` — a one-arity function `fn conn -> :ok end` called when a connection is retired. Defaults to a no-op.

  If an option is invalid — in particular `min_size > max_size`, or a `max_uses` that is neither `:infinity` nor a positive integer — `start_link` must fail startup so that it returns `{:error, reason}`.

- `RecyclingPool.checkout(name, timeout)` — borrow a connection.
  - If a connection is available, hand it out: `{:ok, conn}`.
  - Otherwise, if the pool has fewer than `max_size` connections alive, lazily create one (use count `0`) and hand it out.
  - If the pool is at `max_size` with nothing available, **block** the caller up to `timeout` ms; on success `{:ok, conn}`, otherwise `{:error, :timeout}`. A `timeout` of `0` returns `{:error, :timeout}` immediately.

- `RecyclingPool.checkin(name, conn)` — return a connection. Returns `:ok`. This completes a use: increment the connection's use count.
  - If the connection has reached `:max_uses`, **retire** it (destroy it via `:destroy`, let the total shrink). If a caller is blocked waiting, create a **fresh** connection (use count `0`) for the longest-waiting one instead of handing back the retired one.
  - Otherwise, if a caller is blocked waiting, hand the connection directly to the longest-waiting one; if not, place it back as available.

- `RecyclingPool.stats(name)` — return `%{available: a, in_use: u, total: t, max: max, min: min, max_uses: max_uses}` where `total == a + u`.

## Required behaviors

- **Bounded reuse.** No connection is handed out more than `:max_uses` times; once exhausted it is destroyed and replaced lazily. With `:infinity` no connection is ever retired.
- **Lazy growth up to max**, distinct connections, and reuse of not-yet-exhausted returned connections.
- **Ownership monitoring / crash reclamation.** Monitor the checking-out process; if it dies while holding a connection, reclaim it — this **counts as a use** and may retire the connection (creating a fresh replacement for any waiter). A process that dies while merely blocked waiting is dropped from the waiter queue and never handed a connection.
- **Clean, server-side timeout.** A blocked `checkout` returns `{:error, :timeout}` as a normal value — implement waiting/timeout in the server with a waiter queue and `Process.send_after` / `GenServer.reply`, not via `GenServer.call`'s own timeout.

Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.

## The module with `assign` missing

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
    # TODO
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

Give me only the complete implementation of `assign` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
