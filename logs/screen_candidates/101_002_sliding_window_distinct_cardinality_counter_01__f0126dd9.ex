defmodule SlidingUniqueCounter do
  @moduledoc """
  A `GenServer` that tracks the number of **distinct members** observed for a key
  within a sliding time window.

  Unlike a plain event counter, this module answers *"how many unique things did we
  see in the last N milliseconds"* rather than *"how many events happened"*. Adding
  the same member repeatedly inside the window still contributes exactly one to the
  distinct count.

  ## Design

  Time is divided into fixed-width sub-buckets of `:bucket_ms` milliseconds. An
  observation made at timestamp `t` is placed into the bucket whose index is
  `div(t, bucket_ms)`; each bucket holds a `MapSet` of the distinct members seen
  inside it.

  Answering `distinct_count/3` is therefore the size of the union of the member sets
  of every in-window bucket. A bucket at index `b` starts at `b * bucket_ms`, and is
  included only when

      b * bucket_ms >= now - window_ms

  Inclusion is decided at *bucket* granularity, not per-observation timestamps: a
  member counts if at least one bucket containing it starts inside the window, even
  if the same member was also seen outside the window.

  Keys are tracked independently of one another.

  ## Memory

  A periodic cleanup (scheduled with `Process.send_after/3` every
  `:cleanup_interval_ms`) drops every bucket whose start time is older than
  `now - max_window_ms`, and removes keys that end up with no buckets left. The
  `:cleanup` message is also handled when sent directly to the process, so tests may
  trigger a cleanup pass synchronously (for example via `send/2` followed by a call).

  ## Example

      {:ok, pid} = SlidingUniqueCounter.start_link(bucket_ms: 1_000)
      :ok = SlidingUniqueCounter.add(pid, "page:home", "user:1")
      :ok = SlidingUniqueCounter.add(pid, "page:home", "user:1")
      :ok = SlidingUniqueCounter.add(pid, "page:home", "user:2")
      2 = SlidingUniqueCounter.distinct_count(pid, "page:home", 60_000)
  """

  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000
  @default_max_window_ms 3_600_000

  @type key :: term()
  @type member :: term()
  @type server :: GenServer.server()
  @type clock :: (-> integer())

  @typep bucket_index :: integer()
  @typep buckets :: %{optional(bucket_index()) => MapSet.t()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:clock, :bucket_ms, :cleanup_interval_ms, :max_window_ms]
    defstruct [
      :clock,
      :bucket_ms,
      :cleanup_interval_ms,
      :max_window_ms,
      keys: %{}
    ]
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the counter process.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — width of each internal sub-bucket in milliseconds.
      Defaults to `#{@default_bucket_ms}`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often the periodic cleanup runs, in milliseconds.
      Defaults to `#{@default_cleanup_interval_ms}`. Pass `:infinity` to disable it.
    * `:max_window_ms` — retention horizon used by cleanup; buckets whose start time
      is older than `now - max_window_ms` are removed. Defaults to
      `#{@default_max_window_ms}`.

  Any other option is ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Records that `member` was observed for `key` at the current clock time.

  Repeated additions of the same member within a bucket collapse into a single
  distinct entry. Always returns `:ok`.
  """
  @spec add(server(), key(), member()) :: :ok
  def add(server, key, member) do
    GenServer.call(server, {:add, key, member})
  end

  @doc """
  Returns the number of distinct members observed for `key` within the last
  `window_ms` milliseconds, relative to the current clock time.

  Only buckets whose start time (`bucket_index * bucket_ms`) is at or after
  `now - window_ms` are considered; the result is the size of the union of their
  member sets. Members observed only outside the window are not counted.
  """
  @spec distinct_count(server(), key(), non_neg_integer()) :: non_neg_integer()
  def distinct_count(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:distinct_count, key, window_ms})
  end

  @doc """
  Returns how many keys currently hold any tracked data.

  Once cleanup has removed all expired data, this reports `0`.
  """
  @spec tracked_key_count(server()) :: non_neg_integer()
  def tracked_key_count(server) do
    GenServer.call(server, :tracked_key_count)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)

    unless is_function(clock, 0) do
      raise ArgumentError, ":clock must be a zero-arity function returning milliseconds"
    end

    unless is_integer(bucket_ms) and bucket_ms > 0 do
      raise ArgumentError, ":bucket_ms must be a positive integer"
    end

    unless cleanup_interval_ms == :infinity or
             (is_integer(cleanup_interval_ms) and cleanup_interval_ms > 0) do
      raise ArgumentError, ":cleanup_interval_ms must be a positive integer or :infinity"
    end

    unless is_integer(max_window_ms) and max_window_ms >= 0 do
      raise ArgumentError, ":max_window_ms must be a non-negative integer"
    end

    state = %State{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      max_window_ms: max_window_ms,
      keys: %{}
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:add, key, member}, _from, %State{} = state) do
    index = bucket_index(state, now(state))

    keys =
      Map.update(state.keys, key, %{index => MapSet.new([member])}, fn buckets ->
        Map.update(buckets, index, MapSet.new([member]), &MapSet.put(&1, member))
      end)

    {:reply, :ok, %State{state | keys: keys}}
  end

  def handle_call({:distinct_count, key, window_ms}, _from, %State{} = state) do
    count =
      state.keys
      |> Map.get(key, %{})
      |> union_within(state, now(state) - window_ms)
      |> MapSet.size()

    {:reply, count, state}
  end

  def handle_call(:tracked_key_count, _from, %State{} = state) do
    {:reply, map_size(state.keys), state}
  end

  @impl GenServer
  def handle_info(:cleanup, %State{} = state) do
    state = prune(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_message, %State{} = state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  @spec now(State.t()) :: integer()
  defp now(%State{clock: clock}), do: clock.()

  @spec bucket_index(State.t(), integer()) :: bucket_index()
  defp bucket_index(%State{bucket_ms: bucket_ms}, timestamp), do: div(timestamp, bucket_ms)

  @spec bucket_start(State.t(), bucket_index()) :: integer()
  defp bucket_start(%State{bucket_ms: bucket_ms}, index), do: index * bucket_ms

  # Union of the member sets of every bucket whose start time is >= `cutoff`.
  @spec union_within(buckets(), State.t(), integer()) :: MapSet.t()
  defp union_within(buckets, %State{} = state, cutoff) do
    Enum.reduce(buckets, MapSet.new(), fn {index, members}, acc ->
      if bucket_start(state, index) >= cutoff do
        MapSet.union(acc, members)
      else
        acc
      end
    end)
  end

  # Drops buckets older than the retention horizon, and keys left with no buckets.
  @spec prune(State.t()) :: State.t()
  defp prune(%State{} = state) do
    cutoff = now(state) - state.max_window_ms

    keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        live =
          buckets
          |> Enum.filter(fn {index, _members} -> bucket_start(state, index) >= cutoff end)
          |> Map.new()

        if map_size(live) == 0, do: acc, else: Map.put(acc, key, live)
      end)

    %State{state | keys: keys}
  end

  @spec schedule_cleanup(State.t()) :: :ok
  defp schedule_cleanup(%State{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%State{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end
end