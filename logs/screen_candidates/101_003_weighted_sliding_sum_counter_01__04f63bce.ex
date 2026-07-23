defmodule SlidingSum do
  @moduledoc """
  A `GenServer` that maintains a sliding time-window running **sum of numeric
  amounts** per key using a fixed-width sub-bucket strategy.

  Each recorded event carries a numeric amount (bytes, dollars, points, ...).
  Time is divided into fixed-width sub-buckets of `:bucket_ms` milliseconds.
  Every event is placed into the bucket whose index is `div(timestamp,
  bucket_ms)`, and each bucket accumulates the sum of the amounts placed into
  it. Queries return the total amount whose bucket start time falls within the
  requested sliding window.

  Amounts may be integers or floats and may be negative, so a window sum can be
  positive, zero, or negative. Different keys are tracked independently.

  A periodic cleanup removes buckets — and whole keys — that have fallen outside
  the maximum retention window of 24 hours, keeping memory bounded.
  """

  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000
  @retention_ms 24 * 60 * 60 * 1000

  @typep bucket_index :: integer()
  @typep buckets :: %{optional(bucket_index()) => number()}
  @typep state :: %{
           clock: (-> integer()),
           bucket_ms: pos_integer(),
           cleanup_interval_ms: pos_integer() | :infinity,
           keys: %{optional(term()) => buckets()}
         }

  # Public API

  @doc """
  Starts the `SlidingSum` process.

  Options:

    * `:clock` — zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often to run the periodic cleanup.
      Defaults to `60_000`. Pass `:infinity` to disable.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Records `amount` for `key` at the current clock time.

  `amount` may be any number (integer or float, possibly negative). Always
  returns `:ok`.
  """
  @spec add(GenServer.server(), term(), number()) :: :ok
  def add(server, key, amount) when is_number(amount) do
    GenServer.cast(server, {:add, key, amount})
  end

  @doc """
  Returns the total of all amounts recorded for `key` whose bucket start time
  falls within the last `window_ms` milliseconds relative to the current clock
  time.

  A key with no recorded amounts (or whose amounts have all expired) returns `0`.
  """
  @spec sum(GenServer.server(), term(), non_neg_integer()) :: number()
  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end

  @doc """
  Returns the list of keys currently tracked (those that still have at least one
  stored bucket), in no particular order.

  A server with no data returns `[]`.
  """
  @spec keys(GenServer.server()) :: [term()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  # GenServer callbacks

  @impl true
  @spec init(keyword()) :: {:ok, state()}
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

  @impl true
  def handle_cast({:add, key, amount}, state) do
    now = state.clock.()
    index = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    buckets = Map.update(buckets, index, amount, &(&1 + amount))
    keys = Map.put(state.keys, key, buckets)

    {:noreply, %{state | keys: keys}}
  end

  @impl true
  def handle_call({:sum, key, window_ms}, _from, state) do
    now = state.clock.()
    cutoff = now - window_ms

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {index, amount}, acc ->
        if index * state.bucket_ms >= cutoff, do: acc + amount, else: acc
      end)

    {:reply, total, state}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.keys), state}
  end

  @impl true
  def handle_info(:__cleanup_tick, state) do
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, run_cleanup(state)}
  end

  def handle_info(:cleanup, state) do
    {:noreply, run_cleanup(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Internal helpers

  @spec schedule_cleanup(pos_integer() | :infinity) :: reference() | :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) do
    Process.send_after(self(), :__cleanup_tick, interval_ms)
  end

  @spec run_cleanup(state()) :: state()
  defp run_cleanup(state) do
    now = state.clock.()
    cutoff = now - @retention_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        retained =
          buckets
          |> Enum.filter(fn {index, _amount} -> index * state.bucket_ms >= cutoff end)
          |> Map.new()

        if map_size(retained) == 0, do: acc, else: Map.put(acc, key, retained)
      end)

    %{state | keys: keys}
  end
end