# Implement `handle_cast/2` for `Debouncer`

Implement the `handle_cast/2` clause that handles the `{:debounce, key, delay_ms, func}`
message cast by `call/3`. It must coalesce rapid calls sharing the same `key`:

- First, cancel any timer already pending for `key`. Look up `key` in `state`; if it
  holds a `{timer_ref, _old_func}` entry, cancel that timer with
  `Process.cancel_timer/1` (discarding the previously pending func). If there is no
  entry for `key`, do nothing.
- Then schedule a fresh timer with `Process.send_after/3` that sends `{:fire, key}` to
  the server (`self()`) after `delay_ms` milliseconds.
- Store the new `{timer_ref, func}` under `key` in the state map (replacing any prior
  entry for that key), and return `{:noreply, updated_state}`.

The net effect is that each new call for a key restarts that key's timer and replaces
its pending function, while leaving every other key's timer and function untouched.

```elixir
defmodule Debouncer do
  @moduledoc """
  A `GenServer` that debounces zero-arity function calls on a per-key basis.

  Rapid calls sharing the same key are coalesced: each new call for a key
  resets that key's timer and replaces the pending function, so only the most
  recently supplied function runs once the burst settles (after `delay_ms`
  elapses with no further calls for that key). Different keys are fully
  independent, each with their own timer and schedule.

  ## Example

      {:ok, _pid} = Debouncer.start_link([])

      # Only the last func runs, ~50ms after the final call.
      Debouncer.call(:save, 50, fn -> IO.puts("v1") end)
      Debouncer.call(:save, 50, fn -> IO.puts("v2") end)
      Debouncer.call(:save, 50, fn -> IO.puts("v3") end)
      #=> eventually prints "v3"
  """

  use GenServer

  @doc """
  Starts the debouncer process.

  Accepts a `:name` option for process registration, defaulting to `Debouncer`
  (the module name) when not provided.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Schedules `func` (a zero-arity function) to run after `delay_ms` milliseconds
  on the given `key`.

  If another `call/3` for the same `key` arrives before the pending timer fires,
  the timer is reset and `func` replaces the previously pending function, so only
  the most recent `func` for a burst runs (exactly once).

  Returns `:ok` promptly without blocking on `func`. Targets the process
  registered under the name `Debouncer`.
  """
  @spec call(term(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, func) when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:debounce, key, delay_ms, func}, state) do
    # TODO
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {{_timer_ref, func}, new_state} ->
        # Run the func off the server's reduction path so a slow or crashing
        # func can't wedge the GenServer.
        spawn(fn -> func.() end)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end
end
```