# Implement `handle_call/3`

Implement the `handle_call/3` GenServer callback. It must handle three kinds of
requests — `{:checkout, timeout}`, `{:checkin, conn}`, and `:stats` — using the
struct fields and the private helpers (`assign/3`, `release/2`) already defined
in the module.

**`{:checkout, timeout}` (from `{pid, _tag}`)** — hand out a connection to the
caller. Consider the cases in order:

- If a connection is **available**, pop the head off `available`, mark it in-use
  for `pid` via `assign/3`, and reply `{:ok, conn}`.
- Otherwise, if the pool has room (`total < max`), lazily **create** a new
  connection with the `create` function, bump `total`, seed its use count to `0`
  in `uses`, mark it in-use via `assign/3`, and reply `{:ok, conn}`.
- Otherwise, if `timeout == 0`, reply `{:error, :timeout}` immediately without
  changing state.
- Otherwise, **block** the caller: monitor `pid`, schedule a
  `{:waiter_timeout, mon}` message with `Process.send_after/3` after `timeout`
  ms, enqueue a waiter record `%{from: from, pid: pid, mon: mon, timer: timer}`
  onto `waiters`, and return `{:noreply, state}` (no reply yet — it is delivered
  later via `GenServer.reply/2`).

**`{:checkin, conn}`** — return a connection and reply `:ok`. Look up `conn` in
`in_use`. If it is checked out (`{pid, mon}`), demonitor `mon` (with `:flush`),
remove it from `in_use`, and run it through `release/2` (which completes the use
— bumping the count, retiring or returning the connection, and waking any
waiter). If `conn` is not currently in use, reply `:ok` and leave state
unchanged.

**`:stats`** — reply with the map
`%{available: length(available), in_use: map_size(in_use), total: total,
max: max, min: min, max_uses: max_uses}`, leaving state unchanged.

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
    # TODO
  end

  def handle_call({:checkin, conn}, _from, state) do
    # TODO
  end

  def handle_call(:stats, _from, state) do
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