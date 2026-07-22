defmodule CusumAnomaly do
  @moduledoc """
  A `GenServer` that tracks multiple named numeric streams and detects
  **change points** using a two-sided CUSUM (cumulative sum) algorithm layered
  on top of online mean/variance estimation via Welford's algorithm.

  Unlike a moving average — which smooths a signal and reports its current
  level — this module reports whether a stream has *shifted* into a new
  statistical regime (a higher or lower equilibrium). CUSUM accumulates
  normalized deviations from the running mean; once that accumulation crosses a
  threshold, an alert fires.

  ## Per-push algorithm

  For each pushed value `x` on a stream:

    1. Compute the normalized deviation `z = (x - mean) / max(stddev, epsilon)`
       using the mean/stddev *before* this value is folded in. Until
       `warmup_samples` values have been seen, CUSUM is skipped entirely.
    2. If the pre-update stddev is below `slack`, skip the CUSUM update (a flat
       signal has no meaningful z-score); otherwise update
       `s_high = max(0.0, s_high + z - slack)` and
       `s_low = max(0.0, s_low - z - slack)`.
    3. Fold `x` into Welford's running mean and variance.
    4. If `s_high >= threshold`, emit an upward-shift alert; if
       `s_low >= threshold`, emit a downward-shift alert. On any alert the
       stream's CUSUM and Welford state are fully reset and the stream is frozen
       until `reset/2` is called.

  Streams are independent and identified by an arbitrary `name`.
  """

  use GenServer

  @type stream_name :: term()

  @type status :: :normal | :warming_up

  @type check_result :: %{
          mean: float(),
          stddev: float(),
          s_high: float(),
          s_low: float(),
          samples: non_neg_integer(),
          status: status()
        }

  @type push_result ::
          :ok
          | {:alert, :upward_shift}
          | {:alert, :downward_shift}
          | :warming_up

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the anomaly detector.

  ## Options

    * `:name` — optional process registration name.
    * `:threshold` — alert trigger, a positive float (default `5.0`).
    * `:slack` — CUSUM slack constant, a non-negative float (default `0.5`).
    * `:warmup_samples` — minimum samples before detection activates, a
      positive integer (default `10`).
    * `:epsilon` — minimum stddev floor to avoid division by zero, a positive
      float (default `1.0e-6`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Appends `value` to the named stream and runs the CUSUM/Welford update.

  Returns `:ok` when the value was processed without an alert,
  `{:alert, :upward_shift}` or `{:alert, :downward_shift}` when a change point
  is detected (the stream is reset and frozen), or `:warming_up` when the
  stream still has fewer than `warmup_samples` values or is frozen awaiting an
  explicit `reset/2`.
  """
  @spec push(GenServer.server(), stream_name(), number()) :: push_result()
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Reports the current status of a stream without pushing a value.

  Returns `{:ok, info}` where `info` holds the running `mean`, `stddev`, both
  cumulative sums (`s_high`, `s_low`), the number of `samples`, and a `status`
  of `:warming_up` (fewer than `warmup_samples` samples) or `:normal`. Returns
  `{:error, :no_data}` if the stream is unknown.
  """
  @spec check(GenServer.server(), stream_name()) ::
          {:ok, check_result()} | {:error, :no_data}
  def check(server, name) do
    GenServer.call(server, {:check, name})
  end

  @doc """
  Explicitly resets the named stream's Welford and CUSUM state to zero and
  clears any post-alert freeze, so the stream re-learns from scratch.

  Always returns `:ok`. Does not create a stream that does not already exist.
  """
  @spec reset(GenServer.server(), stream_name()) :: :ok
  def reset(server, name) do
    GenServer.call(server, {:reset, name})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    state = %{
      streams: %{},
      threshold: Keyword.get(opts, :threshold, 5.0),
      slack: Keyword.get(opts, :slack, 0.5),
      warmup_samples: Keyword.get(opts, :warmup_samples, 10),
      epsilon: Keyword.get(opts, :epsilon, 1.0e-6)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream = Map.get(state.streams, name, new_stream())
    {result, stream1} = process_push(stream, value, state)
    streams = Map.put(state.streams, name, stream1)
    {:reply, result, %{state | streams: streams}}
  end

  def handle_call({:check, name}, _from, state) do
    case Map.fetch(state.streams, name) do
      :error ->
        {:reply, {:error, :no_data}, state}

      {:ok, stream} ->
        status =
          if stream.n < state.warmup_samples, do: :warming_up, else: :normal

        info = %{
          mean: stream.mean,
          stddev: stddev(stream),
          s_high: stream.s_high,
          s_low: stream.s_low,
          samples: stream.n,
          status: status
        }

        {:reply, {:ok, info}, state}
    end
  end

  def handle_call({:reset, name}, _from, state) do
    streams =
      if Map.has_key?(state.streams, name) do
        Map.put(state.streams, name, new_stream())
      else
        state.streams
      end

    {:reply, :ok, %{state | streams: streams}}
  end

  # ── Internal helpers ──────────────────────────────────────────────────────

  @spec new_stream() :: map()
  defp new_stream do
    %{n: 0, mean: 0.0, m2: 0.0, s_high: 0.0, s_low: 0.0, alerted: false}
  end

  @spec alerted_stream() :: map()
  defp alerted_stream do
    %{n: 0, mean: 0.0, m2: 0.0, s_high: 0.0, s_low: 0.0, alerted: true}
  end

  @spec process_push(map(), number(), map()) :: {push_result(), map()}
  defp process_push(stream, value, cfg) do
    cond do
      stream.alerted ->
        {:warming_up, stream}

      stream.n < cfg.warmup_samples ->
        {:warming_up, welford_update(stream, value)}

      true ->
        active_push(stream, value, cfg)
    end
  end

  @spec active_push(map(), number(), map()) :: {push_result(), map()}
  defp active_push(stream, value, cfg) do
    sd = stddev(stream)

    if sd < cfg.slack do
      {:ok, welford_update(stream, value)}
    else
      z = (value - stream.mean) / max(sd, cfg.epsilon)
      s_high = max(0.0, stream.s_high + z - cfg.slack)
      s_low = max(0.0, stream.s_low - z - cfg.slack)
      updated = welford_update(%{stream | s_high: s_high, s_low: s_low}, value)
      evaluate(updated, s_high, s_low, cfg)
    end
  end

  @spec evaluate(map(), float(), float(), map()) :: {push_result(), map()}
  defp evaluate(stream, s_high, s_low, cfg) do
    cond do
      s_high >= cfg.threshold ->
        {{:alert, :upward_shift}, alerted_stream()}

      s_low >= cfg.threshold ->
        {{:alert, :downward_shift}, alerted_stream()}

      true ->
        {:ok, stream}
    end
  end

  @spec welford_update(map(), number()) :: map()
  defp welford_update(%{n: n, mean: mean, m2: m2} = stream, x) do
    n1 = n + 1
    delta = x - mean
    mean1 = mean + delta / n1
    delta2 = x - mean1
    m2_1 = m2 + delta * delta2
    %{stream | n: n1, mean: mean1, m2: m2_1}
  end

  @spec stddev(map()) :: float()
  defp stddev(%{n: 0}), do: 0.0
  defp stddev(%{n: n, m2: m2}), do: :math.sqrt(m2 / n)
end