defmodule SlidingSum do
  @moduledoc """
  A `GenServer` that maintains a sliding time-window running **sum of numeric
  amounts** per key using a fixed-width sub-bucket strategy.

  Each recorded event carries a numeric `amount` (an integer or float, possibly
  negative). Time is divided into fixed-width sub-buckets of `:bucket_ms`
  milliseconds; every event is accumulated into the bucket whose index is
  `div(timestamp, bucket_ms)`. A query returns the total amount whose buckets
  fall within the requested sliding window.

  A bucket `b` is considered "inside" a window of width `window_ms` relative to
  `now` exactly when its start time satisfies the inclusive rule
  `b * bucket_ms >= now - window_ms`. The same inclusive rule is applied by the
  periodic cleanup against a fixed 24-hour retention horizon so that memory does
  not grow without bound.

  Keys are tracked independently: an amount added to one key never affects
  another.
  """

  use GenServer

  @typedoc "A key tracked by the server; any term is accepted."
  @type key :: term()

  @typedoc "A zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  @max_retention_ms 24 * 60 * 60 * 1000

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000

  ## Public API

  @doc """
  Starts the `SlidingSum` process.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often the periodic cleanup runs. Defaults to
      `60_000`. Pass `:infinity` to disable periodic cleanup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Records `amount` for `key` at the current clock time.

  `amount` may be any number: an integer or float, and it may be negative.
  Always returns `:ok`.
  """
  @spec add(GenServer.server(), key(), number()) :: :ok
  def add(server, key, amount) when is_number(amount) do
    GenServer.cast(server, {:add, key, amount})
  end

  @doc """
  Returns the total of all amounts recorded for `key` whose buckets fall within
  the last `window_ms` milliseconds relative to the current clock time.

  A key that has had no amounts added returns `0`. The result may be negative or
  zero when negative amounts have been recorded.
  """
  @spec sum(GenServer.server(), key(), non_neg_integer()) :: number()
  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end

  @doc """
  Returns the list of keys currently tracked, in no particular order.

  A key appears only while it still has at least one stored bucket. A server
  with no data returns `[]`.
  """
  @spec keys(GenServer.server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      keys: %{},
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms
    }

    {:ok, schedule_cleanup(state)}
  end

  @impl true
  def handle_cast({:add, key, amount}, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    buckets = Map.update(buckets, bucket, amount, &(&1 + amount))

    {:noreply, %{state | keys: Map.put(state.keys, key, buckets)}}
  end

  @impl true
  def handle_call({:sum, key, window_ms}, _from, state) do
    now = state.clock.()
    horizon = now - window_ms

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {bucket, value}, acc ->
        if bucket * state.bucket_ms >= horizon, do: acc + value, else: acc
      end)

    {:reply, total, state}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.keys), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {:noreply, state |> run_cleanup() |> schedule_cleanup()}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  @spec run_cleanup(map()) :: map()
  defp run_cleanup(state) do
    now = state.clock.()
    horizon = now - @max_retention_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        kept =
          buckets
          |> Enum.filter(fn {bucket, _value} -> bucket * state.bucket_ms >= horizon end)
          |> Map.new()

        if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
      end)

    %{state | keys: keys}
  end

  @spec schedule_cleanup(map()) :: map()
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state), do: state

  defp schedule_cleanup(%{cleanup_interval_ms: interval} = state) do
    Process.send_after(self(), :cleanup, interval)
    state
  end
end