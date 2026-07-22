defmodule CusumAnomaly do
  @moduledoc """
  A `GenServer` that maintains multiple independent named numeric streams and
  detects **change points** using a two-sided CUSUM (cumulative sum) algorithm
  layered on top of an online mean/variance computed with Welford's algorithm.

  Where a moving average tells you the current smoothed level of a signal, this
  module tells you the *inverse*: whether a stream has just shifted into a new
  statistical regime (a sustained upward or downward move away from the mean it
  had previously settled on).

  ## Algorithm

  For every stream the server keeps Welford's running accumulators
  (`n`, `mean`, `M2`) plus two cumulative sums `s_high` and `s_low`. On each
  push of value `x`:

    1. A normalized deviation `z = (x - mean) / max(stddev, epsilon)` is computed
       from the mean/stddev *before* this value is folded in.
    2. While the stream has fewer than `warmup_samples` values, only Welford's
       accumulators are updated and the push reports `:warming_up`.
    3. When the pre-update stddev is below `slack`, the CUSUM step is skipped
       (z-scoring a near-flat signal is meaningless) and the push reports `:ok`.
    4. Otherwise `s_high = max(0, s_high + z - slack)` and
       `s_low = max(0, s_low - z - slack)`; if either reaches `threshold` an
       alert fires, the whole stream state is reset to zero, and the stream is
       frozen until `reset/2` is called.

  Each stream name is fully independent of every other.
  """

  use GenServer

  @type server :: GenServer.server()
  @type stream_name :: term()

  @type info :: %{
          mean: float(),
          stddev: float(),
          s_high: float(),
          s_low: float(),
          samples: non_neg_integer(),
          status: :normal | :warming_up
        }

  @type push_result ::
          :ok
          | {:alert, :upward_shift}
          | {:alert, :downward_shift}
          | :warming_up

  # --- Public API ---------------------------------------------------------

  @doc """
  Starts the anomaly-detection server.

  Options:

    * `:name` — optional process registration name.
    * `:threshold` — positive float alert trigger (default `5.0`).
    * `:slack` — non-negative CUSUM slack constant (default `0.5`).
    * `:warmup_samples` — positive integer minimum samples before detection is
      active (default `10`).
    * `:epsilon` — positive float stddev floor to avoid division-by-zero
      (default `1.0e-6`).

  Options are validated eagerly in the calling process; out-of-range values
  raise `ArgumentError` before any process is started.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 5.0)
    slack = Keyword.get(opts, :slack, 0.5)
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6)
    :ok = validate!(threshold, slack, warmup, epsilon)

    config = %{
      threshold: threshold,
      slack: slack,
      warmup_samples: warmup,
      epsilon: epsilon
    }

    gen_opts =
      case Keyword.get(opts, :name) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, config, gen_opts)
  end

  @doc """
  Appends `value` to the named stream and runs the CUSUM/Welford update.

  Returns `:ok` when the value was processed without alerting,
  `{:alert, :upward_shift}` or `{:alert, :downward_shift}` when a threshold was
  breached (the stream is then reset and frozen), or `:warming_up` when the
  stream is still gathering `warmup_samples` values or is frozen awaiting a
  `reset/2`.

  A non-numeric `value` raises `FunctionClauseError` in the caller.
  """
  @spec push(server(), stream_name(), number()) :: push_result()
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Reports the current status of the named stream without pushing a value.

  Returns `{:ok, info}` with the running mean, population stddev, both CUSUM
  sums, the sample count, and a `:normal`/`:warming_up` status. Returns
  `{:error, :no_data}` when the stream has never been seen.
  """
  @spec check(server(), stream_name()) :: {:ok, info()} | {:error, :no_data}
  def check(server, name) do
    GenServer.call(server, {:check, name})
  end

  @doc """
  Explicitly resets an existing stream's Welford and CUSUM state to zero and
  clears any post-alert freeze, without deleting the stream entry.

  Does nothing (but still returns `:ok`) when the stream is unknown.
  """
  @spec reset(server(), stream_name()) :: :ok
  def reset(server, name) do
    GenServer.call(server, {:reset, name})
  end

  # --- GenServer callbacks ------------------------------------------------

  @impl true
  def init(config) do
    {:ok, %{config: config, streams: %{}}}
  end

  @impl true
  def handle_call({:push, name, value}, _from, state) do
    stream = Map.get(state.streams, name, new_stream())
    {result, stream1} = process_push(stream, value, state.config)
    {:reply, result, %{state | streams: Map.put(state.streams, name, stream1)}}
  end

  @impl true
  def handle_call({:check, name}, _from, state) do
    {:reply, stream_info(Map.get(state.streams, name), state.config), state}
  end

  @impl true
  def handle_call({:reset, name}, _from, state) do
    streams =
      if Map.has_key?(state.streams, name) do
        Map.put(state.streams, name, new_stream())
      else
        state.streams
      end

    {:reply, :ok, %{state | streams: streams}}
  end

  # --- Internal helpers ---------------------------------------------------

  @spec new_stream() :: map()
  defp new_stream do
    %{n: 0, mean: +0.0, m2: +0.0, s_high: +0.0, s_low: +0.0, frozen: false}
  end

  @spec frozen_stream() :: map()
  defp frozen_stream do
    %{new_stream() | frozen: true}
  end

  @spec process_push(map(), number(), map()) :: {push_result(), map()}
  defp process_push(%{frozen: true} = stream, _value, _config) do
    {:warming_up, stream}
  end

  defp process_push(%{n: n} = stream, value, %{warmup_samples: warmup})
       when n < warmup do
    {:warming_up, welford_update(stream, value)}
  end

  defp process_push(stream, value, config) do
    sd = stddev(stream)

    if sd < config.slack do
      {:ok, welford_update(stream, value)}
    else
      active_push(stream, value, config, sd)
    end
  end

  @spec active_push(map(), number(), map(), float()) :: {push_result(), map()}
  defp active_push(stream, value, config, sd) do
    z = (value - stream.mean) / max(sd, config.epsilon)
    s_high = max(+0.0, stream.s_high + z - config.slack)
    s_low = max(+0.0, stream.s_low - z - config.slack)
    updated = welford_update(%{stream | s_high: s_high, s_low: s_low}, value)

    cond do
      s_high >= config.threshold -> {{:alert, :upward_shift}, frozen_stream()}
      s_low >= config.threshold -> {{:alert, :downward_shift}, frozen_stream()}
      true -> {:ok, updated}
    end
  end

  @spec welford_update(map(), number()) :: map()
  defp welford_update(%{n: n, mean: mean, m2: m2} = stream, value) do
    n1 = n + 1
    delta = value - mean
    mean1 = mean + delta / n1
    delta2 = value - mean1
    %{stream | n: n1, mean: mean1, m2: m2 + delta * delta2}
  end

  @spec stddev(map()) :: float()
  defp stddev(%{n: 0}), do: +0.0
  defp stddev(%{n: n, m2: m2}), do: :math.sqrt(m2 / n)

  @spec stream_info(map() | nil, map()) :: {:ok, info()} | {:error, :no_data}
  defp stream_info(nil, _config), do: {:error, :no_data}

  defp stream_info(stream, config) do
    status = if stream.n < config.warmup_samples, do: :warming_up, else: :normal

    info = %{
      mean: stream.mean,
      stddev: stddev(stream),
      s_high: stream.s_high,
      s_low: stream.s_low,
      samples: stream.n,
      status: status
    }

    {:ok, info}
  end

  @spec validate!(term(), term(), term(), term()) :: :ok
  defp validate!(threshold, slack, warmup, epsilon) do
    unless is_number(threshold) and threshold > 0 do
      raise ArgumentError, "threshold must be a positive number"
    end

    unless is_number(slack) and slack >= 0 do
      raise ArgumentError, "slack must be a non-negative number"
    end

    unless is_integer(warmup) and warmup > 0 do
      raise ArgumentError, "warmup_samples must be a positive integer"
    end

    unless is_number(epsilon) and epsilon > 0 do
      raise ArgumentError, "epsilon must be a positive number"
    end

    :ok
  end
end