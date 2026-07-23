# Fill in one @spec

Below: a working module where the `@spec` for
`call/3` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `call/3` missing

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
  # TODO: @spec
  def call(key, delay_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:debounce, key, delay_ms, func}, state) do
    # Cancel any pending timer for this key so the burst is coalesced. If the
    # old timer already fired, its message may be sitting in our queue —
    # cancellation cannot recall it, which is why every arm carries a unique
    # ref: handle_info/2 recognizes and drops the stale message.
    case Map.get(state, key) do
      {_ref, timer, _old_func} -> Process.cancel_timer(timer)
      nil -> :ok
    end

    ref = make_ref()
    timer = Process.send_after(self(), {:fire, key, ref}, delay_ms)
    {:noreply, Map.put(state, key, {ref, timer, func})}
  end

  @impl true
  def handle_info({:fire, key, ref}, state) do
    case Map.get(state, key) do
      {^ref, _timer, func} ->
        # Run the func off the server's reduction path so a slow or crashing
        # func can't wedge the GenServer.
        spawn(fn -> func.() end)
        {:noreply, Map.delete(state, key)}

      _ ->
        # Stale fire: the key was re-debounced (or already fired) after this
        # timer's message was queued, so its func was replaced. Dropping the
        # message keeps the replacement's delay real.
        {:noreply, state}
    end
  end
end
```

The `@spec` attribute only — nothing more.
