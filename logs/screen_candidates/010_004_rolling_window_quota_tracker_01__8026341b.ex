defmodule QuotaTracker do
  @moduledoc """
  A `GenServer` that tracks per-key usage against configurable rolling-window
  quotas.

  Each key accumulates timestamped usage entries. Usage is counted only within a
  rolling window of `window_ms` milliseconds relative to the current time, so old
  entries naturally age out. Expired entries are evicted lazily on every access
  and, in addition, a periodic sweep drops keys whose usage lists have become
  empty so the process does not leak memory.

  The notion of "current time" is injectable via the `:clock` option (a
  zero-arity function returning milliseconds), which makes the behaviour fully
  deterministic and testable.
  """

  use GenServer

  @default_max_window_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A usage key. Any term is accepted."
  @type key :: term()

  @typedoc "A single usage entry: `{recorded_at_ms, amount}`."
  @type entry :: {integer(), number()}

  # Client API

  @doc """
  Starts the `QuotaTracker` process.

  ## Options

    * `:clock` - a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` - an optional name for process registration.
    * `:cleanup_interval_ms` - interval between periodic cleanup passes, in
      milliseconds, or `:infinity` to disable the timer. Defaults to `60_000`.
    * `:max_window_ms` - entries older than this many milliseconds are always
      evicted during a sweep, regardless of any per-call window. Defaults to
      `3_600_000`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Records `amount` units of usage for `key` against `quota` within a rolling
  window of `window_ms` milliseconds.

  Returns `{:ok, remaining}` where `remaining` is `quota - total_usage_in_window`
  after recording. If recording would push usage above `quota`, nothing is
  recorded and `{:error, :quota_exceeded, overage}` is returned, where `overage`
  is how far above the quota the attempt would have gone.
  """
  @spec record(GenServer.server(), key(), number(), number(), integer()) ::
          {:ok, number()} | {:error, :quota_exceeded, number()}
  def record(server, key, amount, quota, window_ms) do
    GenServer.call(server, {:record, key, amount, quota, window_ms})
  end

  @doc """
  Returns `{:ok, remaining}` where `remaining` is `quota - total_usage_in_window`
  for `key`.

  If `key` has no recorded usage, `remaining` equals the full `quota`. This is a
  read-only operation that records nothing but still evicts expired entries.
  """
  @spec remaining(GenServer.server(), key(), number(), integer()) :: {:ok, number()}
  def remaining(server, key, quota, window_ms) do
    GenServer.call(server, {:remaining, key, quota, window_ms})
  end

  @doc """
  Returns `{:ok, total_used}` — the total usage for `key` within the rolling
  window of `window_ms` milliseconds. Returns `{:ok, 0}` if `key` has no
  recorded usage.
  """
  @spec usage(GenServer.server(), key(), integer()) :: {:ok, number()}
  def usage(server, key, window_ms) do
    GenServer.call(server, {:usage, key, window_ms})
  end

  @doc """
  Clears all usage history for `key`. Always returns `:ok`, whether or not the
  key previously existed.
  """
  @spec reset(GenServer.server(), key()) :: :ok
  def reset(server, key) do
    GenServer.call(server, {:reset, key})
  end

  @doc """
  Returns a list of all keys that have any recorded usage entries.

  The list includes keys whose entries may be expired; it is not filtered by any
  window.
  """
  @spec keys(GenServer.server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)

    cleanup_interval_ms =
      Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      usage: %{},
      clock: clock,
      max_window_ms: max_window_ms,
      cleanup_interval_ms: cleanup_interval_ms
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:record, key, amount, quota, window_ms}, _from, state) do
    now = state.clock.()
    entries = evict(Map.get(state.usage, key, []), now, window_ms)
    current = total(entries)
    new_total = current + amount

    if new_total > quota do
      new_usage = Map.put(state.usage, key, entries)
      {:reply, {:error, :quota_exceeded, new_total - quota}, %{state | usage: new_usage}}
    else
      entries = [{now, amount} | entries]
      new_usage = Map.put(state.usage, key, entries)
      {:reply, {:ok, quota - new_total}, %{state | usage: new_usage}}
    end
  end

  @impl true
  def handle_call({:remaining, key, quota, window_ms}, _from, state) do
    now = state.clock.()
    entries = evict(Map.get(state.usage, key, []), now, window_ms)
    new_usage = Map.put(state.usage, key, entries)
    {:reply, {:ok, quota - total(entries)}, %{state | usage: new_usage}}
  end

  @impl true
  def handle_call({:usage, key, window_ms}, _from, state) do
    now = state.clock.()
    entries = evict(Map.get(state.usage, key, []), now, window_ms)
    new_usage = Map.put(state.usage, key, entries)
    {:reply, {:ok, total(entries)}, %{state | usage: new_usage}}
  end

  @impl true
  def handle_call({:reset, key}, _from, state) do
    {:reply, :ok, %{state | usage: Map.delete(state.usage, key)}}
  end

  @impl true
  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.usage), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    state = cleanup(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Internal helpers

  @spec schedule_cleanup(pos_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  @spec cleanup(map()) :: map()
  defp cleanup(state) do
    now = state.clock.()

    new_usage =
      state.usage
      |> Enum.reduce(%{}, fn {key, entries}, acc ->
        case evict(entries, now, state.max_window_ms) do
          [] -> acc
          kept -> Map.put(acc, key, kept)
        end
      end)

    %{state | usage: new_usage}
  end

  @spec evict([entry()], integer(), integer()) :: [entry()]
  defp evict(entries, now, window_ms) do
    cutoff = now - window_ms
    Enum.filter(entries, fn {ts, _amount} -> ts > cutoff end)
  end

  @spec total([entry()]) :: number()
  defp total(entries) do
    Enum.reduce(entries, 0, fn {_ts, amount}, acc -> acc + amount end)
  end
end