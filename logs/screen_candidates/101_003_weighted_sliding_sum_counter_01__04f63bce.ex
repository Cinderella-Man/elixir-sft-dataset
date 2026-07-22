defmodule SlidingSum do
  @moduledoc """
  A `GenServer` that maintains a sliding time-window running **sum of numeric amounts**
  per key using a fixed-width sub-bucket strategy.

  Each recorded event carries a numeric amount (bytes transferred, dollars spent, points
  scored, ...). Queries return the total amount inside the window rather than a count of
  events.

  ## Design

  Time is divided into fixed-width sub-buckets of `:bucket_ms` milliseconds. An event
  recorded at time `t` is accumulated into the bucket whose index is `div(t, bucket_ms)`.
  Each bucket therefore holds the running sum of every amount placed into it.

  A bucket `b` is included in `sum/3` if and only if its start time falls inside the
  sliding window:

      b * bucket_ms >= now - window_ms

  Buckets that start before the window are discarded from the result.

  Amounts may be integers or floats and may be negative, so a window sum may be positive,
  zero or negative.

  ## Memory

  Per-key bucket sums live in `state.keys`, a map of `key => %{bucket_index => sum}`. A
  periodic cleanup (scheduled with `Process.send_after/3` every `:cleanup_interval_ms`)
  drops every bucket whose start time falls outside the 24 hour retention horizon, using
  the same inclusive rule as `sum/3`:

      bucket_start >= now - 86_400_000

  Keys left without buckets are removed entirely, so `state.keys` becomes an empty map
  once all data has expired. A `:cleanup` message may also be sent directly to the
  process to trigger a cleanup pass synchronously from tests.
  """

  use GenServer

  @typedoc "A tracked key. Any term may be used."
  @type key :: term()

  @typedoc "A numeric amount; integers and floats, positive or negative, are allowed."
  @type amount :: number()

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000

  @max_retention_ms 24 * 60 * 60 * 1000

  @doc """
  Starts the sliding-sum server.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — width of each internal sub-bucket in milliseconds. Defaults to
      `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often the periodic cleanup runs, in milliseconds.
      Defaults to `60_000`. Pass `:infinity` to disable it.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Records `amount` for `key` at the current clock time.

  `amount` may be an integer or a float and may be negative, in which case it subtracts
  from the window sum. Always returns `:ok`.
  """
  @spec add(GenServer.server(), key(), amount()) :: :ok
  def add(server, key, amount) when is_number(amount) do
    GenServer.cast(server, {:add, key, amount})
  end

  @doc """
  Returns the total of the amounts recorded for `key` within the last `window_ms`
  milliseconds relative to the current clock time.

  A bucket contributes to the result if and only if its start time satisfies
  `bucket_start >= now - window_ms`. Unknown keys return `0`.
  """
  @spec sum(GenServer.server(), key(), non_neg_integer()) :: number()
  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end

  @doc """
  Returns the list of keys that currently have at least one stored bucket, in no
  particular order.

  A server with no data returns `[]`, and a key whose buckets have all been removed by
  cleanup no longer appears.
  """
  @spec keys(GenServer.server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:add, key, amount}, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

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
      |> Enum.reduce(0, fn {bucket, value}, acc ->
        if bucket * state.bucket_ms >= cutoff, do: acc + value, else: acc
      end)

    {:reply, total, state}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.keys), state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    state = purge_expired(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## Internal helpers

  @spec purge_expired(map()) :: map()
  defp purge_expired(state) do
    now = state.clock.()
    cutoff = now - @max_retention_ms

    keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        kept =
          Map.filter(buckets, fn {bucket, _value} ->
            bucket * state.bucket_ms >= cutoff
          end)

        if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
      end)

    %{state | keys: keys}
  end

  @spec schedule_cleanup(pos_integer() | :infinity) :: reference() | :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end