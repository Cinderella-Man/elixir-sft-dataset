# Fill in the middle: `GraceWatchdog.handle_call/3`

The module below is a complete `GraceWatchdog` GenServer — a heartbeat watchdog that
tolerates a configurable number of consecutive missed intervals before firing a
timeout callback. Every function is present and intact **except** `handle_call/3`,
whose clause bodies have been replaced with `# TODO`.

Implement the four `handle_call/3` clauses that back the public API. Each clause
receives the current `state`, a map keyed by registration `name`, whose values are
entries of the shape
`%{pid, interval_ms, max_misses, fun, misses, ref, timer}`.

- **`{:register, name, pid, interval_ms, max_misses, fun}`** — (re)register `name`.
  First cancel any existing entry for `name` using the `cancel_entry/2` helper (so a
  replacement never leaves a stale timer running). Then mint a fresh reference with
  `make_ref/0`, arm a timer with `Process.send_after(self(), {:tick, name, ref},
  interval_ms)`, build a new entry with `misses: 0` and the new `ref`/`timer`, store
  it under `name`, and reply `:ok`.

- **`{:heartbeat, name}`** — record a heartbeat. If `name` is registered, cancel its
  current timer, mint a fresh reference, arm a new timer for `entry.interval_ms`,
  and store the entry with `misses` reset to `0` and the new `ref`/`timer`, replying
  `:ok`. If `name` is not registered, reply `:ok` and leave the state unchanged
  (harmless no-op).

- **`{:unregister, name}`** — stop monitoring `name` by delegating to
  `cancel_entry/2` (which cancels the timer if present and removes the entry), then
  reply `:ok`.

- **`{:misses, name}`** — reply `{:ok, entry.misses}` when `name` is registered, or
  `{:error, :not_registered}` otherwise. The state is never modified.

Every clause returns `{:reply, reply, new_state}`. Timers are always tagged with a
unique `ref` so that stale ticks (from a reset, replacement, or unregister) can be
ignored by `handle_info/2`.

```elixir
defmodule GraceWatchdog do
  @moduledoc """
  A GenServer that monitors liveness via heartbeats but tolerates a configurable
  number of consecutive missed intervals before firing.

  Each registered entity is expected to periodically call `heartbeat/1`. Every
  `interval_ms` that elapses without a heartbeat records a *miss* and re-arms a
  fresh timer. Only once `max_misses` consecutive misses accumulate does the
  watchdog invoke `on_timeout_fn.(name, miss_count)` (exactly once) and remove the
  registration. Any heartbeat resets the miss counter to zero.

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

  @doc """
  Registers a watchdog for `name`/`pid` that fires `on_timeout_fn` after `max_misses`
  consecutive missed heartbeats spaced `interval_ms` apart. Returns `:ok`.
  """
  @spec register(
          term(),
          pid(),
          non_neg_integer(),
          pos_integer(),
          (term(), pos_integer() -> any())
        ) ::
          :ok
  def register(name, pid, interval_ms, max_misses, on_timeout_fn)
      when is_integer(interval_ms) and interval_ms >= 0 and is_integer(max_misses) and
             max_misses >= 1 and is_function(on_timeout_fn, 2) do
    GenServer.call(__MODULE__, {:register, name, pid, interval_ms, max_misses, on_timeout_fn})
  end

  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @spec misses(term()) :: {:ok, non_neg_integer()} | {:error, :not_registered}
  def misses(name), do: GenServer.call(__MODULE__, {:misses, name})

  ## GenServer callbacks

  @impl true
  def init(_arg), do: {:ok, %{}}

  def handle_call({:register, name, pid, interval_ms, max_misses, fun}, _from, state) do
    # TODO
  end

  @impl true
  def handle_info({:tick, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        misses = entry.misses + 1

        if misses >= entry.max_misses do
          safe_invoke(entry.fun, name, misses)
          {:noreply, Map.delete(state, name)}
        else
          new_ref = make_ref()
          timer = Process.send_after(self(), {:tick, name, new_ref}, entry.interval_ms)
          {:noreply, Map.put(state, name, %{entry | misses: misses, ref: new_ref, timer: timer})}
        end

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

  defp safe_invoke(fun, name, misses) do
    fun.(name, misses)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```