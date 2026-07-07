# Implement `handle_info/2` for `RecurringWatchdog`

Implement the `handle_info/2` GenServer callback. It handles the internal timer
messages that drive the recurring alerts, plus a catch-all for anything else.

There are two clauses to implement:

1. **Timer tick — `{:tick, name, ref}`.** Look up `name` in the state map. If it is
   present **and** the entry's `ref` matches the `ref` carried in the message (pattern
   match `%{ref: ^ref} = entry`), the timer is current, so an alert is due:
   - Invoke the stored callback via `safe_invoke(entry.fun, name)`.
   - Re-arm the recurring alarm: create a fresh reference with `make_ref/0`, schedule a
     new `{:tick, name, new_ref}` message with `Process.send_after/3` after
     `entry.interval_ms`, and store both the new `ref` and `timer` back into the entry.
   - Set the entry's `status` to `:alerting`.
   - Return `{:noreply, state}` with the updated entry stored under `name`.

   If `name` is missing, or its stored `ref` does **not** match the message's `ref`
   (i.e. the timer is stale because the entry was reset, replaced, or unregistered),
   ignore it and return `{:noreply, state}` unchanged.

2. **Catch-all — any other message.** Ignore it and return `{:noreply, state}`
   unchanged.

Below is the complete module. Only the body of `handle_info/2` has been replaced with
`# TODO`; every other function is intact.

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

  @impl true
  def handle_call({:register, name, pid, interval_ms, fun}, _from, state) do
    state = cancel_entry(state, name)
    ref = make_ref()
    timer = Process.send_after(self(), {:tick, name, ref}, interval_ms)

    entry = %{
      pid: pid,
      interval_ms: interval_ms,
      fun: fun,
      status: :healthy,
      ref: ref,
      timer: timer
    }

    {:reply, :ok, Map.put(state, name, entry)}
  end

  def handle_call({:heartbeat, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer)
        ref = make_ref()
        timer = Process.send_after(self(), {:tick, name, ref}, entry.interval_ms)
        {:reply, :ok, Map.put(state, name, %{entry | status: :healthy, ref: ref, timer: timer})}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} -> {:reply, {:ok, entry.status}, state}
      :error -> {:reply, {:error, :not_registered}, state}
    end
  end

  def handle_info({:tick, name, ref}, state) do
    # TODO
  end

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