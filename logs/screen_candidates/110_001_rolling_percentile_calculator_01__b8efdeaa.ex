defmodule Percentile do
  @moduledoc """
  A `GenServer` that maintains rolling windows of numeric samples across many
  independent series and answers percentile queries on demand.

  Each series is identified by an arbitrary `name` term and is fully independent
  of every other series. A single running process manages all of them.

  Two optional windowing constraints may be applied (individually or together):

    * a **time-based** window (`:window_ms`) — a sample recorded at time `t` is
      live while `now - t < window_ms`;
    * a **count-based** window (`:max_samples`) — only the most recently recorded
      `max_samples` samples per series are retained.

  Percentiles use the **nearest-rank** method for exact reproducibility:

      rank  = max(1, ceil(p * n))
      value = s_rank

  where `s_1..s_n` are the live samples sorted ascending (1-indexed).
  """

  use GenServer

  @type name :: term()
  @type sample :: {integer(), number()}

  @default_name Percentile

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts and registers the rolling-percentile process.

  Supported options:

    * `:name` — the registered process name (default: `Percentile`).
    * `:clock` — a zero-arity function returning the current time in
      milliseconds (default: `System.monotonic_time(:millisecond)`).
    * `:window_ms` — a positive integer enabling a time-based window.
    * `:max_samples` — a positive integer enabling a count-based window.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records a numeric `value` into the series `name`, timestamped with the current
  clock time. Always returns `:ok`.
  """
  @spec record(name(), number()) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.cast(@default_name, {:record, name, value})
  end

  @doc """
  Computes the requested `percentile` (a float in `0.0..1.0`) over the currently
  live samples of series `name` using the nearest-rank method.

  Returns `{:ok, value}` where `value` is one of the recorded samples, or
  `{:error, :empty}` when the series has no live samples.
  """
  @spec query(name(), float()) :: {:ok, number()} | {:error, :empty}
  def query(name, percentile)
      when is_float(percentile) and percentile >= +0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @doc """
  Discards all samples for series `name`. Always returns `:ok`.
  """
  @spec reset(name()) :: :ok
  def reset(name) do
    GenServer.call(@default_name, {:reset, name})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      window_ms: Keyword.get(opts, :window_ms),
      max_samples: Keyword.get(opts, :max_samples),
      series: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:record, name, value}, state) do
    now = state.clock.()
    current = Map.get(state.series, name, [])
    updated = cap([{now, value} | current], state.max_samples)
    {:noreply, %{state | series: Map.put(state.series, name, updated)}}
  end

  @impl true
  def handle_call({:query, name, percentile}, _from, state) do
    now = state.clock.()

    live =
      state.series
      |> Map.get(name, [])
      |> live_values(now, state.window_ms)

    {:reply, nearest_rank(live, percentile), state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  # ── Internal helpers ──────────────────────────────────────────────────────

  # Enforce the count-based window; samples are stored newest-first, so keeping
  # the first `max_samples` drops the oldest.
  @spec cap([sample()], pos_integer() | nil) :: [sample()]
  defp cap(samples, nil), do: samples
  defp cap(samples, max_samples), do: Enum.take(samples, max_samples)

  # Apply the time-based window (when configured) and project to sorted values.
  @spec live_values([sample()], integer(), pos_integer() | nil) :: [number()]
  defp live_values(samples, now, window_ms) do
    samples
    |> Enum.filter(fn {ts, _value} -> live?(ts, now, window_ms) end)
    |> Enum.map(fn {_ts, value} -> value end)
    |> Enum.sort()
  end

  @spec live?(integer(), integer(), pos_integer() | nil) :: boolean()
  defp live?(_ts, _now, nil), do: true
  defp live?(ts, now, window_ms), do: now - ts < window_ms

  @spec nearest_rank([number()], float()) :: {:ok, number()} | {:error, :empty}
  defp nearest_rank([], _percentile), do: {:error, :empty}

  defp nearest_rank(sorted, percentile) do
    n = length(sorted)
    rank = max(1, ceil(percentile * n))
    {:ok, Enum.at(sorted, rank - 1)}
  end
end