defmodule CusumAnomaly do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams and detects
  change-points via a two-sided CUSUM algorithm backed by Welford's online
  mean/variance.

  On each push of `x`:

    1. If `samples < warmup_samples`, push to Welford and return `:warming_up`.
    2. Otherwise, z-score `x` against the **prior** mean/stddev:
         z = (x - mean) / max(stddev, epsilon)
    3. Update CUSUMs:
         s_high = max(0.0, s_high + z - slack)
         s_low  = max(0.0, s_low  - z - slack)
    4. Update Welford with `x`.
    5. If `s_high >= threshold`, emit `:upward_shift` and reset ALL state
       (Welford + both CUSUMs) so the detector re-learns the new regime.
    6. Likewise for `s_low >= threshold` → `:downward_shift` + reset.

  State per stream:

      %{
        samples:  non_neg_integer,
        mean:     float,
        m2:       float,             # Welford's sum of squared differences
        s_high:   float,
        s_low:    float
      }

  Global config (not per stream):

      %{threshold, slack, warmup_samples, epsilon}

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec push(GenServer.server(), term(), number()) ::
          :ok | :warming_up | {:alert, :upward_shift | :downward_shift}
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @spec check(GenServer.server(), term()) ::
          {:ok, map()} | {:error, :no_data}
  def check(server, name), do: GenServer.call(server, {:check, name})

  @spec reset(GenServer.server(), term()) :: :ok
  def reset(server, name), do: GenServer.call(server, {:reset, name})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    threshold = Keyword.get(opts, :threshold, 5.0) * 1.0
    slack = Keyword.get(opts, :slack, 0.5) * 1.0
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6) * 1.0

    validate!(threshold, slack, warmup, epsilon)

    {:ok,
     %{
       streams: %{},
       threshold: threshold,
       slack: slack,
       warmup_samples: warmup,
       epsilon: epsilon
     }}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream = stream_for(state, name)
    value = value * 1.0

    cond do
      # Still warming up — update Welford only, no CUSUM yet.
      stream.samples < state.warmup_samples ->
        new_stream = welford_update(stream, value)
        {:reply, :warming_up, put_stream(state, name, new_stream)}

      true ->
        # Z-score against the prior mean/stddev.
        prior_mean = stream.mean
        prior_std = max(welford_stddev(stream), state.epsilon)
        z = (value - prior_mean) / prior_std

        new_s_high = max(0.0, stream.s_high + z - state.slack)
        new_s_low = max(0.0, stream.s_low - z - state.slack)

        # Always update Welford AFTER z-scoring.
        post_welford = welford_update(stream, value)

        updated = %{post_welford | s_high: new_s_high, s_low: new_s_low}

        cond do
          new_s_high >= state.threshold ->
            {:reply, {:alert, :upward_shift}, put_stream(state, name, reset_stream())}

          new_s_low >= state.threshold ->
            {:reply, {:alert, :downward_shift}, put_stream(state, name, reset_stream())}

          true ->
            {:reply, :ok, put_stream(state, name, updated)}
        end
    end
  end

  def handle_call({:check, name}, _from, state) do
    case Map.fetch(state.streams, name) do
      :error ->
        {:reply, {:error, :no_data}, state}

      {:ok, stream} ->
        status = if stream.samples < state.warmup_samples, do: :warming_up, else: :normal

        info = %{
          mean: stream.mean,
          stddev: welford_stddev(stream),
          s_high: stream.s_high,
          s_low: stream.s_low,
          samples: stream.samples,
          status: status
        }

        {:reply, {:ok, info}, state}
    end
  end

  def handle_call({:reset, name}, _from, state) do
    new_streams =
      case Map.fetch(state.streams, name) do
        {:ok, _} -> Map.put(state.streams, name, reset_stream())
        :error -> state.streams
      end

    {:reply, :ok, %{state | streams: new_streams}}
  end

  # ---------------------------------------------------------------------------
  # Welford's online mean and variance
  # ---------------------------------------------------------------------------

  defp welford_update(stream, value) do
    n = stream.samples + 1
    delta = value - stream.mean
    new_mean = stream.mean + delta / n
    delta2 = value - new_mean
    new_m2 = stream.m2 + delta * delta2
    %{stream | samples: n, mean: new_mean, m2: new_m2}
  end

  defp welford_stddev(%{samples: 0}), do: 0.0
  defp welford_stddev(%{samples: n, m2: m2}), do: :math.sqrt(m2 / n)

  # ---------------------------------------------------------------------------
  # Stream helpers
  # ---------------------------------------------------------------------------

  defp stream_for(state, name), do: Map.get(state.streams, name, reset_stream())

  defp put_stream(state, name, stream),
    do: %{state | streams: Map.put(state.streams, name, stream)}

  defp reset_stream do
    %{samples: 0, mean: 0.0, m2: 0.0, s_high: 0.0, s_low: 0.0}
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp validate!(threshold, slack, warmup, epsilon) do
    if threshold <= 0.0, do: raise(ArgumentError, ":threshold must be positive")
    if slack < 0.0, do: raise(ArgumentError, ":slack must be non-negative")
    unless is_integer(warmup) and warmup > 0,
      do: raise(ArgumentError, ":warmup_samples must be a positive integer")
    if epsilon <= 0.0, do: raise(ArgumentError, ":epsilon must be positive")
  end
end
