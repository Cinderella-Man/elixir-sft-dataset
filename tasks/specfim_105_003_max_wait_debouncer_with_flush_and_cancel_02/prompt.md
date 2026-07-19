# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`start_link/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `start_link/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `start_link/1` missing

```elixir
defmodule MaxWaitDebouncer do
  @moduledoc """
  A `GenServer` debouncer with a maximum-wait guarantee and manual flush/cancel.

  Like a normal debouncer it coalesces rapid same-key calls (resetting the timer
  and replacing the pending func), but it also guarantees the pending func fires
  no later than `max_ms` after the burst's first call — so a sustained burst
  can't starve execution forever. `flush/1` runs the pending func immediately;
  `cancel/1` drops it.
  """

  use GenServer

  @doc """
  Starts the debouncer. Accepts a `:name` option, defaulting to `MaxWaitDebouncer`.
  """
  # TODO: @spec
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Schedules `func` for `key`, coalescing with `delay_ms` but guaranteeing a fire
  within `max_ms` of the burst's first call. Returns `:ok` promptly.
  """
  @spec call(term(), non_neg_integer(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, max_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_integer(max_ms) and
             max_ms >= delay_ms and
             is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, max_ms, func})
  end

  @doc "Immediately runs the pending func for `key` (if any) and clears state."
  @spec flush(term()) :: :ok
  def flush(key), do: GenServer.call(__MODULE__, {:flush, key})

  @doc "Discards the pending func for `key` without running it."
  @spec cancel(term()) :: :ok
  def cancel(key), do: GenServer.call(__MODULE__, {:cancel, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, max_ms, func}, state) do
    now = mono_ms()

    first_at =
      case Map.get(state, key) do
        %{timer: ref, first_at: at} ->
          Process.cancel_timer(ref)
          at

        nil ->
          now
      end

    remaining_until_max = max(0, first_at + max_ms - now)
    fire_in = max(0, min(delay_ms, remaining_until_max))
    ref = Process.send_after(self(), {:fire, key}, fire_in)

    entry = %{timer: ref, func: func, first_at: first_at}
    {:noreply, Map.put(state, key, entry)}
  end

  @impl true
  def handle_call({:flush, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref, func: func}, new_state} ->
        Process.cancel_timer(ref)
        run(func)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:cancel, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref}, new_state} ->
        Process.cancel_timer(ref)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {%{func: func}, new_state} ->
        run(func)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end

  defp run(func), do: spawn(fn -> func.() end)

  defp mono_ms, do: System.monotonic_time(:millisecond)
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
