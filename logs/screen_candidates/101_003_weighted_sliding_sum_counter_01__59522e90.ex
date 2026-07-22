defmodule SlidingSum do
  @moduledoc """
  A `GenServer` that maintains a sliding time-window running sum of numeric
  amounts per key, using a fixed-width sub-bucket strategy.

  Each recorded event carries a numeric amount (bytes transferred, dollars
  spent, points scored, ...). Time is divided into fixed-width sub-buckets of
  `:bucket_ms` milliseconds each; an event recorded at timestamp `t` lands in
  bucket `div(t, bucket_ms)` and that bucket accumulates the sum of every
  amount placed in it.

  When answering `sum/3`, a bucket `b` is included in the total if and only if
  its start time falls within the sliding window, that is:

      b * bucket_ms >= now - window_ms

  Buckets that start before the window are discarded from the result.

  Amounts may be integers or floats and may be negative, so a window sum may be
  positive, zero, or negative.

  Keys are tracked independently. To bound memory usage, a periodic cleanup
  (scheduled with `Process.send_after/3`) drops buckets that have fallen outside
  the maximum retained window, and removes keys once they hold no buckets at
  all. A `:cleanup` message may also be sent directly to the process to trigger
  the same sweep synchronously (useful in tests).

  ## Example

      {:ok, pid} = SlidingSum.start_link([])
      :ok = SlidingSum.add(pid, "conn:a", 120)
      :ok = SlidingSum.add(pid, "conn:a", -20)
      100 = SlidingSum.sum(pid, "conn:a", 5_000)
      ["conn:a"] = SlidingSum.keys(pid)
  """

  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A tracked key. Any term may be used."
  @type key :: term()

  @typedoc "Zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  @typedoc "Bucket index, derived as `div(timestamp_ms, bucket_ms)`."
  @type bucket :: integer()

  @typedoc "Internal server state."
  @type state :: %{
          clock: clock(),
          bucket_ms: pos_integer(),
          cleanup_interval_ms: pos_integer() | :infinity,
          max_window_ms: pos_integer(),
          keys: %{optional(key()) => %{optional(bucket()) => number()}}
        }

  # Buckets older than this many milliseconds are dropped by the periodic
  # cleanup. It is generous enough to cover any reasonable query window while
  # still bounding memory growth.
  @max_window_ms 3_600_000

  ## Public API

  @doc """
  Starts the sliding-sum server.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional name to register the process under.
    * `:cleanup_interval_ms` — how often the periodic cleanup runs, in
      milliseconds. Defaults to `60_000`. Pass `:infinity` to disable it.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Records `amount` for `key` at the current clock time.

  `amount` may be an integer or a float, and may be negative (in which case it
  subtracts from the window sum). Always returns `:ok`.
  """
  @spec add(GenServer.server(), key(), number()) :: :ok
  def add(server, key, amount) when is_number(amount) do
    GenServer.cast(server, {:add, key, amount})
  end

  @doc """
  Returns the total of all amounts recorded for `key` whose bucket starts within
  the last `window_ms` milliseconds of the current clock time.

  A key with no recorded amounts (or whose amounts all fall outside the window)
  sums to `0`.
  """
  @spec sum(GenServer.server(), key(), non_neg_integer()) :: number()
  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end

  @doc """
  Returns the list of keys that currently have at least one stored bucket, in no
  particular order.

  Returns `[]` when the server holds no data, and a key disappears from the list
  once cleanup has removed every one of its buckets.
  """
  @spec keys(GenServer.server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  ## GenServer callbacks

  @impl GenServer
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      max_window_ms: Keyword.get(opts, :max_window_ms, @max_window_ms),
      keys: %{}
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:add, key, amount}, state) do
    bucket = div(state.clock.(), state.bucket_ms)

    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, amount, &(&1 + amount))

    {:noreply, %{state | keys: Map.put(state.keys, key, buckets)}}
  end

  @impl GenServer
  def handle_call({:sum, key, window_ms}, _from, state) do
    now = state.clock.()
    cutoff = now - window_ms

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {bucket, amount}, acc ->
        if bucket * state.bucket_ms >= cutoff, do: acc + amount, else: acc
      end)

    {:reply, total, state}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.keys), state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    state = prune(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## Internal helpers

  @spec schedule_cleanup(state()) :: :ok
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval}) when is_integer(interval) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  # Drops every bucket whose start time falls outside the maximum retained
  # window, then drops any key left without buckets, so `state.keys` becomes an
  # empty map once all data has expired.
  @spec prune(state()) :: state()
  defp prune(state) do
    cutoff = state.clock.() - state.max_window_ms

    keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        live =
          Map.filter(buckets, fn {bucket, _amount} ->
            bucket * state.bucket_ms >= cutoff
          end)

        if map_size(live) == 0, do: acc, else: Map.put(acc, key, live)
      end)

    %{state | keys: keys}
  end
end