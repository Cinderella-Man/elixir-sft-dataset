# Overflow Connection Pool

Write me an Elixir module called `OverflowPool` (a `GenServer`) that manages a pool of reusable connections with **poolboy-style overflow semantics**. A "connection" is an opaque term produced by a factory function — a PID, a reference, or any value.

The pool keeps a fixed base of persistent connections but can create a bounded number of **temporary overflow connections** under load. When an overflow connection is no longer needed, it is destroyed rather than kept, so the pool shrinks back to its base size during quiet periods.

The full module is provided below with one function left unimplemented. Your job is to implement the private `remove_waiter_by_mon/2` function.

## `remove_waiter_by_mon/2`

`remove_waiter_by_mon(queue, mon)` takes a waiter `:queue` and a monitor reference `mon`, and removes the single waiter whose `:mon` field equals `mon`.

- Each element of the queue is a waiter map of the form `%{from: ..., pid: ..., mon: ..., timer: ...}`.
- If a waiter with a matching `:mon` is found, return `{:ok, waiter, rest}` where `waiter` is the matching map and `rest` is a **queue** containing all the other waiters with their original relative order preserved.
- If no waiter matches, return `:error`.
- At most one waiter can match, since each waiting caller is monitored with a distinct reference.

This helper is used both when a blocked `checkout` times out (`{:waiter_timeout, mon}`) and when a waiting caller's process dies (`{:DOWN, ref, ...}`), so it must return the removed waiter (so its timer/monitor can be cleaned up) along with the pruned queue.

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
    # TODO
  end
end
```