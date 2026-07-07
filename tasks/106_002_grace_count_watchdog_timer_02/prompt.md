# Implement `handle_info/2` for `GraceWatchdog`

Implement the `handle_info/2` callback. It handles the scheduled `{:tick, name, ref}`
messages sent by `Process.send_after/3`, plus a catch-all clause for any unrelated
message.

For a `{:tick, name, ref}` message:

- Look up `name` in the state. If there is no entry, or there is an entry whose current
  `:ref` does **not** match the incoming `ref`, the tick is stale (the registration was
  reset by a heartbeat, replaced, or unregistered) — ignore it and return the state
  unchanged with `{:noreply, state}`.
- If the entry exists and its `:ref` matches the incoming `ref`, this is a genuine missed
  interval: increment the entry's `:misses` count by one.
  - If the new miss count has reached `max_misses`, the threshold is met. Invoke the
    stored callback via `safe_invoke(entry.fun, name, misses)` (passing the new miss
    count, which equals `max_misses`), remove the registration from state with
    `Map.delete/2`, and return `{:noreply, ...}`. The callback fires exactly once and the
    registration does not persist.
  - Otherwise (still below the threshold), arm a fresh timer for another `interval_ms`:
    generate a new reference with `make_ref/0`, schedule a new `{:tick, name, new_ref}`
    with `Process.send_after/3`, and store the updated entry (new miss count, new `:ref`,
    new `:timer`) back into state before returning `{:noreply, ...}`.

Any other message must be ignored: return `{:noreply, state}` unchanged.

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

  @spec register(term(), pid(), non_neg_integer(), pos_integer(), (term(), pos_integer() -> any())) :: :ok
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

  @impl true
  def handle_call({:register, name, pid, interval_ms, max_misses, fun}, _from, state) do
    state = cancel_entry(state, name)
    ref = make_ref()
    timer = Process.send_after(self(), {:tick, name, ref}, interval_ms)

    entry = %{
      pid: pid,
      interval_ms: interval_ms,
      max_misses: max_misses,
      fun: fun,
      misses: 0,
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
        {:reply, :ok, Map.put(state, name, %{entry | misses: 0, ref: ref, timer: timer})}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  def handle_call({:misses, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} -> {:reply, {:ok, entry.misses}, state}
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

  defp safe_invoke(fun, name, misses) do
    fun.(name, misses)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```