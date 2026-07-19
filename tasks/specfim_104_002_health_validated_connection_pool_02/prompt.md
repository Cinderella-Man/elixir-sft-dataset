# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`checkout/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `checkout/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `checkout/2` missing

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

  # TODO: @spec
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
    create = Keyword.get(opts, :create, fn -> make_ref() end)
    validate = Keyword.get(opts, :validate, fn _ -> true end)
    destroy = Keyword.get(opts, :destroy, fn _ -> :ok end)

    cond do
      not (is_integer(max) and max >= 0) ->
        {:stop, {:invalid_option, :max_size}}

      not (is_integer(min) and min >= 0) ->
        {:stop, {:invalid_option, :min_size}}

      min > max ->
        {:stop, {:invalid_option, :min_size_gt_max_size}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      not is_function(validate, 1) ->
        {:stop, {:invalid_option, :validate}}

      not is_function(destroy, 1) ->
        {:stop, {:invalid_option, :destroy}}

      true ->
        available = for _ <- 1..min//1, do: create.()

        {:ok,
         %__MODULE__{
           available: available,
           total: min,
           max: max,
           min: min,
           create: create,
           validate: validate,
           destroy: destroy
         }}
    end
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
