defmodule QuotaTracker do
  @moduledoc """
  A `GenServer` that tracks per-key usage against configurable rolling-window quotas.

  Each key accumulates timestamped usage entries. A rolling window of `window_ms`
  milliseconds determines which entries count toward a quota for a given call: an
  entry recorded at time `T` stops being counted once the clock reaches `T + window_ms`.

  The per-call `window_ms` only controls *counting* — it never removes anything from
  storage. Stored entries are evicted only once they age past the tracker-wide
  `:max_window_ms`, which happens lazily on access and via a periodic sweep. As a
  result, an entry that falls outside one call's small window is still counted by a
  later call that uses a larger window (as long as it is younger than `:max_window_ms`).

  ## Options

    * `:clock` - a zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` - optional name for process registration.
    * `:max_window_ms` - entries older than this (from the current time) are always
      evicted, regardless of a call's `window_ms`. Defaults to `3_600_000` (1 hour).
    * `:cleanup_interval_ms` - interval for the periodic sweep. May be `:infinity`
      to disable automatic sweeps. Defaults to `60_000`.
  """

  use GenServer

  @default_max_window_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  @typedoc "Any term used as a usage key."
  @type key :: term()

  @typedoc "A single usage entry: `{recorded_at_ms, amount}`."
  @type entry :: {integer(), non_neg_integer()}

  @typedoc "Internal server state."
  @type state :: %{
          clock: (-> integer()),
          max_window_ms: non_neg_integer(),
          cleanup_interval_ms: non_neg_integer() | :infinity,
          data: %{optional(key()) => [entry()]}
        }

  # Public API

  @doc """
  Starts the tracker process.

  Accepts `:clock`, `:name`, `:max_window_ms` and `:cleanup_interval_ms` options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Records `amount` units of usage for `key` against `quota` within `window_ms`.

  Returns `{:ok, remaining}` where `remaining` is `quota - total_usage_in_window`
  after recording. Returns `{:error, :quota_exceeded, overage}` when recording would
  push usage above `quota`; in that case nothing is recorded (all-or-nothing).
  """
  @spec record(GenServer.server(), key(), non_neg_integer(), non_neg_integer(),
          non_neg_integer()) ::
          {:ok, integer()} | {:error, :quota_exceeded, non_neg_integer()}
  def record(server, key, amount, quota, window_ms) do
    GenServer.call(server, {:record, key, amount, quota, window_ms})
  end

  @doc """
  Returns `{:ok, remaining}` where `remaining` is `quota - total_usage_in_window`.

  If the key has no recorded usage, `remaining` equals `quota`. This is read-only but
  still performs lazy cleanup of stored entries older than `:max_window_ms`.
  """
  @spec remaining(GenServer.server(), key(), non_neg_integer(), non_neg_integer()) ::
          {:ok, integer()}
  def remaining(server, key, quota, window_ms) do
    GenServer.call(server, {:remaining, key, quota, window_ms})
  end

  @doc """
  Returns `{:ok, total_used}` — the total usage for `key` within `window_ms`.

  Returns `{:ok, 0}` if the key has no recorded usage.
  """
  @spec usage(GenServer.server(), key(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def usage(server, key, window_ms) do
    GenServer.call(server, {:usage, key, window_ms})
  end

  @doc """
  Clears all usage history for `key`. Returns `:ok` regardless of prior state.
  """
  @spec reset(GenServer.server(), key()) :: :ok
  def reset(server, key) do
    GenServer.call(server, {:reset, key})
  end

  @doc """
  Returns a list of all keys that have any recorded usage entries.

  The list is not filtered by any window and may include keys whose entries are
  expired but not yet swept.
  """
  @spec keys(GenServer.server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  # GenServer callbacks

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)
    cleanup_interval_ms =
      Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      max_window_ms: max_window_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      data: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:record, key, amount, quota, window_ms}, _from, state) do
    now = state.clock.()
    {kept, data} = prune_key(state.data, key, now, state.max_window_ms)
    current = usage_in_window(kept, now, window_ms)
    new_total = current + amount

    if new_total > quota do
      overage = new_total - quota
      {:reply, {:error, :quota_exceeded, overage}, %{state | data: data}}
    else
      entries = [{now, amount} | kept]
      new_state = %{state | data: Map.put(data, key, entries)}
      {:reply, {:ok, quota - new_total}, new_state}
    end
  end

  def handle_call({:remaining, key, quota, window_ms}, _from, state) do
    now = state.clock.()
    {kept, data} = prune_key(state.data, key, now, state.max_window_ms)
    used = usage_in_window(kept, now, window_ms)
    {:reply, {:ok, quota - used}, %{state | data: data}}
  end

  def handle_call({:usage, key, window_ms}, _from, state) do
    now = state.clock.()
    {kept, data} = prune_key(state.data, key, now, state.max_window_ms)
    used = usage_in_window(kept, now, window_ms)
    {:reply, {:ok, used}, %{state | data: data}}
  end

  def handle_call({:reset, key}, _from, state) do
    {:reply, :ok, %{state | data: Map.delete(state.data, key)}}
  end

  def handle_call(:keys, _from, state) do
    keys =
      state.data
      |> Enum.filter(fn {_key, entries} -> entries != [] end)
      |> Enum.map(fn {key, _entries} -> key end)

    {:reply, keys, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()
    data = sweep(state.data, now, state.max_window_ms)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | data: data}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Internal helpers

  @spec schedule_cleanup(non_neg_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  @spec prune_key(%{optional(key()) => [entry()]}, key(), integer(), non_neg_integer()) ::
          {[entry()], %{optional(key()) => [entry()]}}
  defp prune_key(data, key, now, max_window_ms) do
    case Map.fetch(data, key) do
      :error ->
        {[], data}

      {:ok, entries} ->
        kept = Enum.filter(entries, fn {t, _amount} -> now - t < max_window_ms end)
        {kept, Map.put(data, key, kept)}
    end
  end

  @spec usage_in_window([entry()], integer(), non_neg_integer()) :: non_neg_integer()
  defp usage_in_window(entries, now, window_ms) do
    entries
    |> Enum.filter(fn {t, _amount} -> now - t < window_ms end)
    |> Enum.reduce(0, fn {_t, amount}, acc -> acc + amount end)
  end

  @spec sweep(%{optional(key()) => [entry()]}, integer(), non_neg_integer()) ::
          %{optional(key()) => [entry()]}
  defp sweep(data, now, max_window_ms) do
    Enum.reduce(data, %{}, fn {key, entries}, acc ->
      kept = Enum.filter(entries, fn {t, _amount} -> now - t < max_window_ms end)
      if kept == [], do: acc, else: Map.put(acc, key, kept)
    end)
  end
end