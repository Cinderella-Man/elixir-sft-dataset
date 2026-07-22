defmodule Percentile do
  @moduledoc """
  A `GenServer` maintaining rolling windows of numeric samples across many
  independent series, computing percentiles on demand.

  A single running process manages any number of **series**, each identified by an
  arbitrary term (the series `name`). Samples recorded into one series never affect
  another.

  ## Windows

  Two independent, optionally-combined windowing strategies are supported and are
  configured when the process starts:

    * `:window_ms` — a **time-based** window. A sample recorded at time `t` stays live
      while `now - t < window_ms`, and expires once `now - t >= window_ms`. Expiration
      is evaluated at query time, so advancing the clock and then querying immediately
      reflects the newly-expired samples.

    * `:max_samples` — a **count-based** window. Only the most recently recorded
      `max_samples` samples of a series are retained; recording a sample that pushes the
      series over the limit drops that series' oldest sample.

  If neither option is given, samples are retained indefinitely.

  ## Percentiles

  Percentiles use the **nearest-rank** method, so results are exact, reproducible, and
  always one of the recorded samples. For `n` live samples sorted ascending as
  `s_1..s_n` (1-indexed) and a percentile `p` in `0.0..1.0`:

      rank  = max(1, ceil(p * n))
      value = s_rank

  Hence `p = 0.0` yields the minimum live sample and `p = 1.0` the maximum.

  ## Clock

  All timestamps come from the `:clock` function given at startup (by default
  `System.monotonic_time(:millisecond)`), which lets tests drive time deterministically.

  ## Example

      iex> {:ok, _pid} = Percentile.start_link(window_ms: 60_000)
      iex> Enum.each(1..100, &Percentile.record(:latency, &1))
      iex> Percentile.query(:latency, 0.95)
      {:ok, 95}
      iex> Percentile.reset(:latency)
      :ok
      iex> Percentile.query(:latency, 0.95)
      {:error, :empty}
  """

  use GenServer

  @typedoc "The identifier of a series; any term."
  @type series :: term()

  @typedoc "A recorded sample value."
  @type value :: number()

  @typedoc "A percentile expressed as a float in the inclusive range `0.0..1.0`."
  @type percentile :: float()

  @typedoc "Options accepted by `start_link/1`."
  @type option ::
          {:name, GenServer.name()}
          | {:clock, (-> integer())}
          | {:window_ms, pos_integer()}
          | {:max_samples, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct clock: nil, window_ms: nil, max_samples: nil, series: %{}

    @type t :: %__MODULE__{
            clock: (-> integer()),
            window_ms: pos_integer() | nil,
            max_samples: pos_integer() | nil,
            # series name => {queue of {timestamp, value} oldest-first, count}
            series: %{optional(term()) => {:queue.queue({integer(), number()}), non_neg_integer()}}
          }
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the percentile server and registers it under a name.

  ## Options

    * `:name` — the name to register the process under. Defaults to `Percentile`.
    * `:clock` — a zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`. Every timestamp used
      for window expiration comes from this function.
    * `:window_ms` — a positive integer enabling a time-based window. A sample recorded
      at `t` is live while `now - t < window_ms`. Omitted means no time-based expiry.
    * `:max_samples` — a positive integer enabling a count-based window, retaining only
      the most recent `max_samples` samples per series. Omitted means unbounded.

  Both `:window_ms` and `:max_samples` may be given together; both constraints then apply.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records `value` into the series `name`, timestamped with the current clock time.

  Returns `:ok`.
  """
  @spec record(series(), value()) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.cast(__MODULE__, {:record, name, value})
  end

  @doc """
  Computes `percentile` over the currently-live samples of the series `name`.

  `percentile` is a float in the inclusive range `0.0..1.0` (e.g. `0.95` for p95). Uses
  the nearest-rank method, so the result is always one of the recorded samples.

  Returns `{:ok, value}`, or `{:error, :empty}` if the series has no live samples —
  because it was never recorded to, all its samples expired, or it was reset.
  """
  @spec query(series(), percentile()) :: {:ok, value()} | {:error, :empty}
  def query(name, percentile) when is_float(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(__MODULE__, {:query, name, percentile})
  end

  @doc """
  Discards all samples for the series `name`. Returns `:ok`.
  """
  @spec reset(series()) :: :ok
  def reset(name) do
    GenServer.call(__MODULE__, {:reset, name})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    window_ms = Keyword.get(opts, :window_ms)
    max_samples = Keyword.get(opts, :max_samples)

    with :ok <- validate_clock(clock),
         :ok <- validate_positive(:window_ms, window_ms),
         :ok <- validate_positive(:max_samples, max_samples) do
      {:ok, %State{clock: clock, window_ms: window_ms, max_samples: max_samples, series: %{}}}
    end
  end

  @impl GenServer
  def handle_cast({:record, name, value}, %State{} = state) do
    now = state.clock.()
    {queue, count} = Map.get(state.series, name, {:queue.new(), 0})

    {queue, count} = {:queue.in({now, value}, queue), count + 1}
    {queue, count} = enforce_max_samples(queue, count, state.max_samples)

    {:noreply, %State{state | series: Map.put(state.series, name, {queue, count})}}
  end

  @impl GenServer
  def handle_call({:query, name, percentile}, _from, %State{} = state) do
    case Map.fetch(state.series, name) do
      :error ->
        {:reply, {:error, :empty}, state}

      {:ok, entry} ->
        now = state.clock.()
        {queue, count} = expire(entry, now, state.window_ms)
        state = %State{state | series: Map.put(state.series, name, {queue, count})}
        {:reply, nearest_rank(queue, count, percentile), state}
    end
  end

  def handle_call({:reset, name}, _from, %State{} = state) do
    {:reply, :ok, %State{state | series: Map.delete(state.series, name)}}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec validate_clock(term()) :: :ok | {:stop, term()}
  defp validate_clock(clock) when is_function(clock, 0), do: :ok
  defp validate_clock(other), do: {:stop, {:invalid_option, {:clock, other}}}

  @spec validate_positive(atom(), term()) :: :ok | {:stop, term()}
  defp validate_positive(_key, nil), do: :ok
  defp validate_positive(_key, value) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(key, value), do: {:stop, {:invalid_option, {key, value}}}

  # Drops the oldest samples until the series holds at most `max_samples` of them.
  @spec enforce_max_samples(:queue.queue(), non_neg_integer(), pos_integer() | nil) ::
          {:queue.queue(), non_neg_integer()}
  defp enforce_max_samples(queue, count, nil), do: {queue, count}

  defp enforce_max_samples(queue, count, max) when count > max do
    {_dropped, queue} = :queue.out(queue)
    enforce_max_samples(queue, count - 1, max)
  end

  defp enforce_max_samples(queue, count, _max), do: {queue, count}

  # Drops every sample whose age has reached the time window. Samples are queued in
  # recording order, and the clock is monotonic, so the queue is ordered oldest-first by
  # timestamp: we can stop at the first still-live sample.
  @spec expire({:queue.queue(), non_neg_integer()}, integer(), pos_integer() | nil) ::
          {:queue.queue(), non_neg_integer()}
  defp expire(entry, _now, nil), do: entry

  defp expire({queue, count}, now, window_ms) do
    case :queue.peek(queue) do
      {:value, {timestamp, _value}} when now - timestamp >= window_ms ->
        {_dropped, queue} = :queue.out(queue)
        expire({queue, count - 1}, now, window_ms)

      _empty_or_live ->
        {queue, count}
    end
  end

  # Nearest-rank percentile: rank = max(1, ceil(p * n)), value = s_rank.
  @spec nearest_rank(:queue.queue(), non_neg_integer(), percentile()) ::
          {:ok, value()} | {:error, :empty}
  defp nearest_rank(_queue, 0, _percentile), do: {:error, :empty}

  defp nearest_rank(queue, count, percentile) do
    rank = max(1, ceil(percentile * count))

    value =
      queue
      |> :queue.to_list()
      |> Enum.map(fn {_timestamp, value} -> value end)
      |> Enum.sort()
      |> Enum.at(rank - 1)

    {:ok, value}
  end
end