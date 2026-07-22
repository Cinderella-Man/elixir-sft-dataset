defmodule SlidingSum do
  @moduledoc """
  A `GenServer` that maintains a sliding time-window running **sum of numeric amounts**
  per key, using a sub-bucket strategy.

  Each recorded event carries a numeric amount (bytes transferred, dollars spent, points
  scored, …). Queries return the *total amount* within the window rather than a count of
  events.

  ## Design

  Time is divided into fixed-width sub-buckets of `:bucket_ms` milliseconds. An event
  recorded at timestamp `t` is placed into the bucket whose index is `div(t, bucket_ms)`,
  and each bucket accumulates the sum of the amounts placed into it.

  A call to `sum/3` includes a bucket `b` if and only if its *start time* falls within the
  sliding window, i.e. `b * bucket_ms >= now - window_ms`. Buckets that start before the
  window are discarded from the total.

  Amounts may be integers or floats, and may be negative — a negative amount subtracts
  from the running window sum, so a sum may be negative or zero. A key that has never had
  an amount added sums to `0`.

  ## Memory

  Per-key bucket sums live in `state.keys`, a map of `key => %{bucket_index => sum}`.
  A periodic cleanup (scheduled with `Process.send_after/3`, controlled by
  `:cleanup_interval_ms`) drops buckets that have fallen outside the maximum retained
  window, and drops keys entirely once they hold no buckets. A `:cleanup` message may also
  be sent directly to the process to trigger the sweep synchronously (useful in tests).
  """

  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A key under which amounts are accumulated."
  @type key :: term()

  @typedoc "A numeric amount; may be an integer or a float, and may be negative."
  @type amount :: number()

  @typedoc "A zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  @typedoc "The `GenServer` reference used by the client API."
  @type server :: GenServer.server()

  # Buckets older than this many milliseconds are dropped by the periodic cleanup.
  @max_window_ms 3_600_000

  defstruct clock: nil,
            bucket_ms: @default_bucket_ms,
            cleanup_interval_ms: @default_cleanup_interval_ms,
            keys: %{}

  @typedoc "Internal server state."
  @type t :: %__MODULE__{
          clock: clock(),
          bucket_ms: pos_integer(),
          cleanup_interval_ms: non_neg_integer() | :infinity,
          keys: %{optional(key()) => %{optional(integer()) => amount()}}
        }

  ## Public API

  @doc """
  Starts the `SlidingSum` server.

  ## Options

    * `:clock` — a zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket, in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often the periodic cleanup runs, in milliseconds.
      Defaults to `60_000`. Pass `:infinity` to disable periodic cleanup.

  ## Examples

      iex> {:ok, pid} = SlidingSum.start_link([])
      iex> SlidingSum.sum(pid, "nobody", 1_000)
      0

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Records `amount` for `key` at the current clock time.

  `amount` may be any number — integer or float, positive or negative. Negative amounts
  subtract from the running window sum. Always returns `:ok`.

  ## Examples

      iex> {:ok, pid} = SlidingSum.start_link([])
      iex> SlidingSum.add(pid, "conn:a", 512)
      :ok

  """
  @spec add(server(), key(), amount()) :: :ok
  def add(server, key, amount) when is_number(amount) do
    GenServer.cast(server, {:add, key, amount})
  end

  @doc """
  Returns the total of all amounts recorded for `key` within the last `window_ms`
  milliseconds, relative to the current clock time.

  A bucket is included if and only if its start time falls inside the window, that is
  `bucket_index * bucket_ms >= now - window_ms`. Amounts outside the window are not
  included. Unknown keys sum to `0`.

  ## Examples

      iex> {:ok, pid} = SlidingSum.start_link([])
      iex> :ok = SlidingSum.add(pid, "conn:a", 10)
      iex> :ok = SlidingSum.add(pid, "conn:a", 2.5)
      iex> SlidingSum.sum(pid, "conn:a", 60_000)
      12.5

  """
  @spec sum(server(), key(), non_neg_integer()) :: amount()
  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

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

    state = %__MODULE__{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      keys: %{}
    }

    schedule_cleanup(state)
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
      |> Enum.reduce(0, fn {bucket, bucket_sum}, acc ->
        if bucket * state.bucket_ms >= cutoff, do: acc + bucket_sum, else: acc
      end)

    {:reply, total, state}
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

  @spec schedule_cleanup(t()) :: :ok
  defp schedule_cleanup(%__MODULE__{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%__MODULE__{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  # Drops buckets that start before the maximum retained window, then drops any key left
  # with no buckets, so that `state.keys` becomes an empty map once all data has expired.
  @spec prune(t()) :: t()
  defp prune(state) do
    now = state.clock.()
    cutoff = now - @max_window_ms

    keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        live =
          buckets
          |> Enum.filter(fn {bucket, _sum} -> bucket * state.bucket_ms >= cutoff end)
          |> Map.new()

        if map_size(live) == 0, do: acc, else: Map.put(acc, key, live)
      end)

    %{state | keys: keys}
  end
end