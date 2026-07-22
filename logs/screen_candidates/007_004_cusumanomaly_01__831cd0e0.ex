defmodule CusumAnomaly do
  @moduledoc """
  A `GenServer` that tracks multiple named numeric streams and flags
  **change points** using a two-sided CUSUM (cumulative sum) detector layered on
  top of an online mean/variance estimator (Welford's algorithm).

  Where a moving average tells you the *current* smoothed value of a signal,
  this module tells you the opposite: whether a stream has recently *shifted*
  into a new statistical regime (a higher or lower equilibrium than before).

  ## How it works

  For each stream the server keeps Welford's running `n`, `mean` and `M2`
  accumulators, plus two cumulative sums `s_high` and `s_low`. On every push the
  value is z-scored against the mean/stddev *before* the update, the CUSUMs are
  advanced by that normalized deviation (minus a `slack` dead-band), and only
  then is Welford's state updated. When either CUSUM crosses `threshold` the
  stream emits an alert, wipes all of its state to zero, and freezes until the
  operator calls `reset/2`.

  Streams with different names are fully independent.
  """

  use GenServer

  @type server :: GenServer.server()
  @type stream_name :: term()
  @type push_result ::
          :ok
          | :warming_up
          | {:alert, :upward_shift}
          | {:alert, :downward_shift}

  @type check_info :: %{
          mean: float(),
          stddev: float(),
          s_high: float(),
          s_low: float(),
          samples: non_neg_integer(),
          status: :normal | :warming_up
        }

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the anomaly detector.

  Options:

    * `:name` — optional process registration name.
    * `:threshold` — alert trigger, a positive number (default `5.0`).
    * `:slack` — CUSUM slack constant, a non-negative number (default `0.5`).
    * `:warmup_samples` — minimum samples before detection activates, a positive
      integer (default `10`).
    * `:epsilon` — minimum stddev floor to avoid division-by-zero, a positive
      number (default `1.0e-6`).

  Options are validated eagerly in the calling process: out-of-range values
  raise `ArgumentError` before any process is started.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    cfg = build_config(opts)

    server_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, cfg, server_opts)
  end

  @doc """
  Appends `value` to the named stream and runs the CUSUM/Welford update.

  Returns:

    * `:ok` — value processed, no alert fired;
    * `{:alert, :upward_shift}` — upper CUSUM breached `threshold` (state reset);
    * `{:alert, :downward_shift}` — lower CUSUM breached `threshold` (state reset);
    * `:warming_up` — the stream has fewer than `warmup_samples` values, or is
      frozen after a previous alert awaiting an explicit `reset/2`.

  If both directions breach simultaneously, `:upward_shift` wins.
  """
  @spec push(server(), stream_name(), number()) :: push_result()
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Reports a stream's current status without pushing a value.

  Returns `{:ok, info}` where `info` is a map with `:mean`, `:stddev`,
  `:s_high`, `:s_low`, `:samples` and `:status` (`:warming_up` while
  `samples < warmup_samples`, otherwise `:normal`).

  Returns `{:error, :no_data}` if the stream is completely unknown.
  """
  @spec check(server(), stream_name()) :: {:ok, check_info()} | {:error, :no_data}
  def check(server, name) do
    GenServer.call(server, {:check, name})
  end

  @doc """
  Explicitly resets a stream's Welford and CUSUM state to zero and clears any
  post-alert freeze.

  Does not create a stream that does not already exist. Always returns `:ok`.
  """
  @spec reset(server(), stream_name()) :: :ok
  def reset(server, name) do
    GenServer.call(server, {:reset, name})
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  @doc false
  def init(cfg) do
    {:ok, %{cfg: cfg, streams: %{}}}
  end

  @impl true
  @doc false
  def handle_call({:push, name, value}, _from, state) do
    stream = Map.get(state.streams, name, fresh_stream())

    if stream.frozen do
      {:reply, :warming_up, state}
    else
      {result, updated} = process_push(stream, value, state.cfg)
      streams = Map.put(state.streams, name, updated)
      {:reply, result, %{state | streams: streams}}
    end
  end

  def handle_call({:check, name}, _from, state) do
    case Map.fetch(state.streams, name) do
      :error ->
        {:reply, {:error, :no_data}, state}

      {:ok, stream} ->
        {:reply, {:ok, build_info(stream, state.cfg)}, state}
    end
  end

  def handle_call({:reset, name}, _from, state) do
    if Map.has_key?(state.streams, name) do
      streams = Map.put(state.streams, name, fresh_stream())
      {:reply, :ok, %{state | streams: streams}}
    else
      {:reply, :ok, state}
    end
  end

  # ------------------------------------------------------------------
  # Internal: push processing
  # ------------------------------------------------------------------

  @spec process_push(map(), number(), map()) :: {push_result(), map()}
  defp process_push(stream, value, cfg) do
    %{n: n, mean: mean} = stream
    stddev = stddev_of(stream)

    cond do
      n < cfg.warmup_samples ->
        {:warming_up, welford_update(stream, value)}

      stddev < cfg.slack ->
        {:ok, welford_update(stream, value)}

      true ->
        run_cusum(stream, value, mean, stddev, cfg)
    end
  end

  @spec run_cusum(map(), number(), float(), float(), map()) :: {push_result(), map()}
  defp run_cusum(stream, value, mean, stddev, cfg) do
    z = (value - mean) / max(stddev, cfg.epsilon)
    s_high = max(+0.0, stream.s_high + z - cfg.slack)
    s_low = max(+0.0, stream.s_low - z - cfg.slack)

    advanced = welford_update(%{stream | s_high: s_high, s_low: s_low}, value)

    cond do
      s_high >= cfg.threshold -> {{:alert, :upward_shift}, alerted_stream()}
      s_low >= cfg.threshold -> {{:alert, :downward_shift}, alerted_stream()}
      true -> {:ok, advanced}
    end
  end

  @spec welford_update(map(), number()) :: map()
  defp welford_update(%{n: n, mean: mean, m2: m2} = stream, value) do
    x = value * 1.0
    new_n = n + 1
    delta = x - mean
    new_mean = mean + delta / new_n
    delta2 = x - new_mean
    %{stream | n: new_n, mean: new_mean, m2: m2 + delta * delta2}
  end

  @spec stddev_of(map()) :: float()
  defp stddev_of(%{n: n, m2: m2}) do
    variance = if n > 0, do: m2 / n, else: +0.0
    :math.sqrt(variance)
  end

  @spec build_info(map(), map()) :: check_info()
  defp build_info(stream, cfg) do
    status = if stream.n < cfg.warmup_samples, do: :warming_up, else: :normal

    %{
      mean: stream.mean,
      stddev: stddev_of(stream),
      s_high: stream.s_high,
      s_low: stream.s_low,
      samples: stream.n,
      status: status
    }
  end

  @spec fresh_stream() :: map()
  defp fresh_stream do
    %{n: 0, mean: +0.0, m2: +0.0, s_high: +0.0, s_low: +0.0, frozen: false}
  end

  @spec alerted_stream() :: map()
  defp alerted_stream do
    %{fresh_stream() | frozen: true}
  end

  # ------------------------------------------------------------------
  # Internal: option validation
  # ------------------------------------------------------------------

  @spec build_config(keyword()) :: map()
  defp build_config(opts) do
    threshold = Keyword.get(opts, :threshold, 5.0)
    slack = Keyword.get(opts, :slack, 0.5)
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6)

    validate_positive_number(:threshold, threshold)
    validate_non_negative_number(:slack, slack)
    validate_positive_integer(:warmup_samples, warmup)
    validate_positive_number(:epsilon, epsilon)

    %{
      threshold: threshold * 1.0,
      slack: slack * 1.0,
      warmup_samples: warmup,
      epsilon: epsilon * 1.0
    }
  end

  @spec validate_positive_number(atom(), term()) :: :ok
  defp validate_positive_number(key, value) do
    unless is_number(value) and value > 0 do
      raise ArgumentError,
            "#{key} must be a positive number, got: #{inspect(value)}"
    end

    :ok
  end

  @spec validate_non_negative_number(atom(), term()) :: :ok
  defp validate_non_negative_number(key, value) do
    unless is_number(value) and value >= 0 do
      raise ArgumentError,
            "#{key} must be a non-negative number, got: #{inspect(value)}"
    end

    :ok
  end

  @spec validate_positive_integer(atom(), term()) :: :ok
  defp validate_positive_integer(key, value) do
    unless is_integer(value) and value > 0 do
      raise ArgumentError,
            "#{key} must be a positive integer, got: #{inspect(value)}"
    end

    :ok
  end
end