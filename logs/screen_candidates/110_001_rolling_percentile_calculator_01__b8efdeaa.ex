defmodule Percentile do
  @moduledoc """
  A `GenServer` that maintains rolling windows of numeric samples across many
  independent series and computes percentiles on demand using the
  nearest-rank method.

  A single running process manages any number of series, each identified by an
  arbitrary `name` term. Series are fully independent: recording, querying, or
  resetting one series never affects another.

  Two optional windowing constraints may be configured (individually or
  together):

    * a **time-based** window (`:window_ms`) — a sample recorded at time `t` is
      live while `now - t < window_ms`, and expires once `now - t >= window_ms`;
    * a **count-based** window (`:max_samples`) — only the most recently
      recorded `max_samples` samples per series are retained.

  Time is obtained exclusively through the configured `:clock` function so that
  expiration can be driven deterministically in tests.
  """

  use GenServer

  @typedoc "The identifier of a series; any term is allowed."
  @type name :: term()

  @typedoc "A recorded numeric sample."
  @type value :: number()

  @typedoc "Internal representation of a stored sample as `{timestamp_ms, value}`."
  @type sample :: {integer(), value()}

  # --- Public API ---------------------------------------------------------

  @doc """
  Starts and registers the percentile server.

  Supported options:

    * `:name` — the name to register the process under. Default: `Percentile`.
    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Default: `fn -> System.monotonic_time(:millisecond) end`.
    * `:window_ms` — a positive integer enabling a time-based window.
    * `:max_samples` — a positive integer enabling a count-based window.

  Both `:window_ms` and `:max_samples` may be supplied together.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records a numeric `value` into the series `name`, timestamped with the
  current clock time. Always returns `:ok`.
  """
  @spec record(name(), value()) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(__MODULE__, {:record, name, value})
  end

  @doc """
  Computes the `percentile` (a float in `0.0..1.0`) over the currently-live
  samples of series `name` using the nearest-rank method.

  Returns `{:ok, value}` where `value` is one of the recorded samples, or
  `{:error, :empty}` when the series has no live samples.
  """
  @spec query(name(), float()) :: {:ok, value()} | {:error, :empty}
  def query(name, percentile)
      when is_float(percentile) and percentile >= +0.0 and percentile <= 1.0 do
    GenServer.call(__MODULE__, {:query, name, percentile})
  end

  @doc """
  Discards all samples for series `name`. Always returns `:ok`.
  """
  @spec reset(name()) :: :ok
  def reset(name) do
    GenServer.call(__MODULE__, {:reset, name})
  end

  # --- GenServer callbacks ------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    window_ms = Keyword.get(opts, :window_ms)
    max_samples = Keyword.get(opts, :max_samples)

    state = %{
      clock: clock,
      window_ms: validate_positive(window_ms, :window_ms),
      max_samples: validate_positive(max_samples, :max_samples),
      series: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    existing = Map.get(state.series, name, [])
    updated = trim_count([{now, value} | existing], state.max_samples)
    {:reply, :ok, %{state | series: Map.put(state.series, name, updated)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    now = state.clock.()
    samples = Map.get(state.series, name, [])

    live_values =
      samples
      |> live(now, state.window_ms)
      |> Enum.map(fn {_ts, value} -> value end)
      |> Enum.sort()

    {:reply, percentile_of(live_values, percentile), state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  # --- Internal helpers ---------------------------------------------------

  @spec validate_positive(term(), atom()) :: pos_integer() | nil
  defp validate_positive(nil, _key), do: nil

  defp validate_positive(value, _key) when is_integer(value) and value > 0, do: value

  defp validate_positive(value, key) do
    raise ArgumentError, "#{inspect(key)} must be a positive integer, got: #{inspect(value)}"
  end

  @spec trim_count([sample()], pos_integer() | nil) :: [sample()]
  defp trim_count(samples, nil), do: samples
  defp trim_count(samples, max_samples), do: Enum.take(samples, max_samples)

  @spec live([sample()], integer(), pos_integer() | nil) :: [sample()]
  defp live(samples, _now, nil), do: samples

  defp live(samples, now, window_ms) do
    Enum.filter(samples, fn {ts, _value} -> now - ts < window_ms end)
  end

  @spec percentile_of([value()], float()) :: {:ok, value()} | {:error, :empty}
  defp percentile_of([], _percentile), do: {:error, :empty}

  defp percentile_of(sorted, percentile) do
    n = length(sorted)
    rank = max(1, ceil(percentile * n))
    {:ok, Enum.at(sorted, rank - 1)}
  end
end