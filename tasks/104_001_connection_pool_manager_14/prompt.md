# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `checkout` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Connection Pool Manager

Write me an Elixir module called `Pool` (a `GenServer`) that manages a pool of reusable connections. A "connection" is just an opaque term the pool hands out and takes back — it can be a PID, a reference, or any value produced by a factory function you call.

## Public API

- `Pool.start_link(opts)` — start and register the pool process. Support these options:
  - `:name` — an atom to register the process under. All the other API functions are called with this name.
  - `:max_size` — the maximum number of connections the pool may ever have alive at once. Defaults to `10`.
  - `:min_size` — the number of connections to create **eagerly** when the pool starts. Defaults to `0`. Must be `<= max_size`.
  - `:create` — a zero-arity function returning a **new** connection. Defaults to `fn -> make_ref() end`. Every call must return a distinct connection.

- `Pool.checkout(name, timeout)` — borrow a connection.
  - If a connection is available, return `{:ok, conn}` immediately.
  - If none is available but the pool has fewer than `max_size` connections alive, lazily create one (via the `:create` function), hand it out, and return `{:ok, conn}`.
  - If none is available and the pool is already at `max_size`, **block** the caller for up to `timeout` milliseconds waiting for one to be returned. If a connection becomes available in time, return `{:ok, conn}`. Otherwise return `{:error, :timeout}`.
  - A `timeout` of `0` means: return `{:error, :timeout}` right away if nothing is currently available.

- `Pool.checkin(name, conn)` — return a previously checked-out connection to the pool. Returns `:ok`. If another caller is currently blocked waiting in `checkout`, the returned connection should be handed directly to the longest-waiting one.

- `Pool.stats(name)` — return a map `%{available: a, in_use: u, total: t, max: max, min: min}` where `total == a + u`, describing the current state of the pool.

## Required behaviors

- **Lazy growth up to max.** Connections are only created on demand (beyond the `min_size` created at startup), and the pool never creates more than `max_size` connections total. Returned connections are reused rather than recreated.

- **Distinct connections.** No connection is ever handed to two callers at the same time. Two simultaneous checkouts must return two different connections.

- **Ownership monitoring / crash reclamation.** When a process checks out a connection, the pool must monitor it. If that process dies (for any reason) while still holding the connection, the pool must reclaim the connection automatically and make it available again (handing it to a waiting caller if there is one) — without leaking it.

- **Clean timeout.** `checkout` must return `{:error, :timeout}` as a normal value when it cannot get a connection in time. It must **not** crash the caller or the pool. (In particular, don't rely on `GenServer.call`'s own timeout to signal this — implement the waiting/timeout logic inside the server, e.g. with a waiter queue and `Process.send_after` / `GenServer.reply`.)

Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.

## The module with `checkout` missing

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

  def checkout(name, timeout) when is_integer(timeout) and timeout >= 0 do
    # TODO
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

Give me only the complete implementation of `checkout` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
