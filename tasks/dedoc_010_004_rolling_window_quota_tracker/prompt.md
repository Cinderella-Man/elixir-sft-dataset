# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule QuotaTracker do
  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_max_window_ms 3_600_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

  def __default_clock__, do: System.monotonic_time(:millisecond)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name_opt, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opt)
  end

  def record(server, key, amount, quota, window_ms) do
    GenServer.call(server, {:record, key, amount, quota, window_ms})
  end

  def remaining(server, key, quota, window_ms) do
    GenServer.call(server, {:remaining, key, quota, window_ms})
  end

  def usage(server, key, window_ms) do
    GenServer.call(server, {:usage, key, window_ms})
  end

  def reset(server, key) do
    GenServer.call(server, {:reset, key})
  end

  def keys(server) do
    GenServer.call(server, :keys)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      entries: %{},
      max_window_ms: max_window_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:record, key, amount, quota, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    current_usage = sum_usage(current_entries)

    if current_usage + amount > quota do
      overage = current_usage + amount - quota

      # Lazily clean up state using max_window_ms
      retained_entries = evict_expired(entries, now, state.max_window_ms)

      new_entries =
        if retained_entries == [] do
          Map.delete(state.entries, key)
        else
          Map.put(state.entries, key, retained_entries)
        end

      {:reply, {:error, :quota_exceeded, overage}, %{state | entries: new_entries}}
    else
      new_entry = %{amount: amount, recorded_at: now}

      # Retain up to max_window_ms, append the new entry
      retained_entries = evict_expired(entries, now, state.max_window_ms)
      updated = [new_entry | retained_entries]
      new_entries = Map.put(state.entries, key, updated)

      remaining = quota - (current_usage + amount)
      {:reply, {:ok, remaining}, %{state | entries: new_entries}}
    end
  end

  def handle_call({:remaining, key, quota, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    current_usage = sum_usage(current_entries)

    # Lazily clean up state using max_window_ms
    retained_entries = evict_expired(entries, now, state.max_window_ms)

    new_entries =
      if retained_entries == [] do
        Map.delete(state.entries, key)
      else
        Map.put(state.entries, key, retained_entries)
      end

    remaining = quota - current_usage
    {:reply, {:ok, remaining}, %{state | entries: new_entries}}
  end

  def handle_call({:usage, key, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    total = sum_usage(current_entries)

    # Lazily clean up state using max_window_ms
    retained_entries = evict_expired(entries, now, state.max_window_ms)

    new_entries =
      if retained_entries == [] do
        Map.delete(state.entries, key)
      else
        Map.put(state.entries, key, retained_entries)
      end

    {:reply, {:ok, total}, %{state | entries: new_entries}}
  end

  def handle_call({:reset, key}, _from, state) do
    new_entries = Map.delete(state.entries, key)
    {:reply, :ok, %{state | entries: new_entries}}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.entries), state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_entries =
      state.entries
      |> Enum.map(fn {key, entries} ->
        {key, evict_expired(entries, now, state.max_window_ms)}
      end)
      |> Enum.reject(fn {_key, entries} -> entries == [] end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | entries: surviving_entries}}
  end

  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  defp evict_expired(entries, now, window_ms) do
    cutoff = now - window_ms

    Enum.filter(entries, fn entry ->
      entry.recorded_at > cutoff
    end)
  end

  defp sum_usage(entries) do
    Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount end)
  end
end
```
