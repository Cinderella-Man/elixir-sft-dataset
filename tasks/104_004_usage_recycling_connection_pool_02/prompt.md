Implement the private `release/2` function. It represents the completion of a single
use of a connection (a normal `checkin`, or reclamation after the holder crashes). It
receives the connection and the current state (the connection has *already* been
removed from `in_use` by the caller) and must return the updated state.

First bump the connection's use count: read its current count from the `uses` map
(defaulting to `0`), add one, and drop the old `uses` entry for `conn`.

Then decide whether the connection is exhausted using `retire?/2` with the new count
and `state.max_uses`:

- **Retire it.** Call `state.destroy.(conn)` and decrement `total`. Then check the
  waiter queue with `:queue.out/1`:
  - If a waiter is waiting, cancel its timer (`Process.cancel_timer/1`), create a
    **fresh** connection via `state.create.()`, record it as `in_use` for that waiter
    (`{waiter.pid, waiter.mon}`), reply to the waiter with `{:ok, new}` via
    `GenServer.reply/2`, and return the state with the waiter dequeued, `total`
    incremented back, and the new connection's use count set to `0`.
  - If no waiter, just return the state (the total shrinks; the connection is gone).

- **Keep it.** Check the waiter queue with `:queue.out/1`:
  - If a waiter is waiting, cancel its timer, hand `conn` directly to that waiter
    (record it as `in_use`, reply `{:ok, conn}`), dequeue the waiter, and store the
    connection's new use count.
  - If no waiter, put `conn` back at the head of `available` and store its new use
    count.

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

  defp release(conn, state) do
    # TODO
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