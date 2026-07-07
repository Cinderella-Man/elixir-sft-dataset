# Implement `handle_call/3` for `RecurringWatchdog`

Implement the `handle_call/3` GenServer callback. It handles four kinds of
synchronous requests, and every clause replies to the caller and returns the
(possibly updated) state.

- `{:register, name, pid, interval_ms, fun}` — start (or replace) monitoring for
  `name`. First cancel any existing entry for `name` using `cancel_entry/2` (so a
  prior timer can never fire). Create a fresh tag with `make_ref()`, arm a timer
  with `Process.send_after(self(), {:tick, name, ref}, interval_ms)`, and store an
  entry map holding `pid`, `interval_ms`, `fun`, `status: :healthy`, the `ref`, and
  the `timer`. Reply `:ok` with the updated state.

- `{:heartbeat, name}` — record a heartbeat. If `name` is registered, cancel its
  current timer with `Process.cancel_timer/1`, mint a new `ref`, re-arm a fresh
  `interval_ms` timer, and store the entry with `status: :healthy` plus the new
  `ref`/`timer`. If `name` is unknown, it is a harmless no-op. Reply `:ok` in both
  cases.

- `{:unregister, name}` — stop monitoring `name` by dropping its entry via
  `cancel_entry/2` (canceling its timer). Reply `:ok`. Unknown names are no-ops.

- `{:status, name}` — reply `{:ok, status}` (the entry's current `:healthy` or
  `:alerting`) when `name` is registered, or `{:error, :not_registered}` otherwise.
  The state is unchanged.

```elixir
defmodule RecurringWatchdog do
  @moduledoc """
  A GenServer that monitors liveness via heartbeats and keeps re-alerting every
  interval while an entity stays silent.

  Each registered entity is expected to periodically call `heartbeat/1`. If no
  heartbeat arrives within `interval_ms`, `on_timeout_fn.(name)` is invoked and the
  status becomes `:alerting`; the watchdog then re-arms another interval and fires
  again, repeating until a heartbeat (which resets status to `:healthy`) or an
  unregister.

  Timers are tagged with a unique reference so stale timers (from a reset or an
  unregister) can never fire spuriously.
  """

  use GenServer

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @spec register(term(), pid(), non_neg_integer(), (term() -> any())) :: :ok
  def register(name, pid, interval_ms, on_timeout_fn)
      when is_integer(interval_ms) and interval_ms >= 0 and is_function(on_timeout_fn, 1) do
    GenServer.call(__MODULE__, {:register, name, pid, interval_ms, on_timeout_fn})
  end

  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @spec status(term()) :: {:ok, :healthy | :alerting} | {:error, :not_registered}
  def status(name), do: GenServer.call(__MODULE__, {:status, name})

  ## GenServer callbacks

  @impl true
  def init(_arg), do: {:ok, %{}}

  def handle_call({:register, name, pid, interval_ms, fun}, _from, state) do
    # TODO
  end

  @impl true
  def handle_info({:tick, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        safe_invoke(entry.fun, name)
        new_ref = make_ref()
        timer = Process.send_after(self(), {:tick, name, new_ref}, entry.interval_ms)
        {:noreply, Map.put(state, name, %{entry | status: :alerting, ref: new_ref, timer: timer})}

      _ ->
        # Stale timer (reset/unregistered/replaced) — ignore.
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp cancel_entry(state, name) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer)
        Map.delete(state, name)

      :error ->
        state
    end
  end

  defp safe_invoke(fun, name) do
    fun.(name)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```