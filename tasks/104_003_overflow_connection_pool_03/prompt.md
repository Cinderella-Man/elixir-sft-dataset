# Fill in the middle: `OverflowPool.handle_call/3`

Below is a complete `OverflowPool` module — a `GenServer` connection pool with
poolboy-style overflow semantics — with the body of every `handle_call/3` clause
removed and replaced with `# TODO`. Your job is to implement `handle_call/3`.

The pool keeps a fixed base of persistent connections plus a bounded number of
temporary overflow connections. The struct fields you will work with are:
`:available` (a list of free connections), `:in_use` (a map of `conn => {pid, mon}`),
`:waiters` (an Erlang `:queue` of `%{from, pid, mon, timer}` maps), `:total` (count of
live connections), `:size`, `:max_overflow`, `:create`, and `:destroy`. Two helpers are
provided: `assign/3` (monitors the borrowing pid and records the connection as in-use)
and `release/2` (hands a freed connection to a waiter, or destroys it if overflow, or
returns it to `:available`).

Implement the three `handle_call/3` clauses:

1. **`{:checkout, timeout}`** — borrow a connection. `from` is `{pid, tag}`; bind `pid`.
   - If `state.available` is non-empty, pop the head connection, hand it out with
     `{:reply, {:ok, conn}, ...}`, and record it via `assign/3` with the remaining
     available list.
   - Otherwise, if `state.total < state.size + state.max_overflow`, lazily create a
     connection with `state.create.()`, hand it out, and record it via `assign/3` while
     incrementing `:total`.
   - Otherwise, if `timeout == 0`, reply immediately with `{:error, :timeout}`.
   - Otherwise, block the caller: monitor `pid`, schedule a `{:waiter_timeout, mon}`
     message with `Process.send_after/3` after `timeout` ms, build a waiter map
     `%{from: from, pid: pid, mon: mon, timer: timer}`, enqueue it into `state.waiters`,
     and return `{:noreply, ...}` (the reply happens later via `GenServer.reply`).

2. **`{:checkin, conn}`** — return a connection, always replying `:ok`.
   - Pop `conn` from `state.in_use`. If it was in use as `{_pid, mon}`, demonitor `mon`
     with `[:flush]` and run `release/2` on the connection with the updated `:in_use`.
   - If `conn` was not in use, reply `:ok` with the state unchanged.

3. **`:stats`** — reply with a map:
   `%{available: length(available), in_use: map_size(in_use), total: total,
   size: size, max_overflow: max_overflow, overflow: max(0, total - size)}`,
   leaving the state unchanged.

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

  def handle_call({:checkout, timeout}, from, state) do
    # TODO
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