# Fill in the middle: `percentile_of/2`

Implement the private `percentile_of/2` helper. It is called from the `:query`
handler with the series' live sample **values already sorted in ascending order**
and the requested `percentile` (a float in `0.0..1.0`).

It must compute the percentile using the **nearest-rank** method and behave as
follows:

- If the sorted list is empty, return `{:error, :empty}`.
- Otherwise, let `n` be the number of samples. Compute
  `rank = max(1, ceil(percentile * n))` and return `{:ok, value}` where `value`
  is the sample at position `rank` (1-indexed) in the ascending list — i.e. the
  element at zero-based index `rank - 1`.

Consequences this must satisfy: `percentile = 0.0` yields the minimum sample,
`percentile = 1.0` yields the maximum sample, and for samples `1..100` a
percentile of `0.50` yields `50`, `0.95` yields `95`, and `0.99` yields `99`.

```elixir
defmodule Percentile do
  @moduledoc """
  A GenServer that maintains rolling windows of numeric samples across many
  independent **series** and computes percentiles on demand using the
  nearest-rank method.

  A single running process manages any number of series, each identified by an
  arbitrary `name` term. Two independent windowing strategies are supported and
  may be combined:

    * time-based (`:window_ms`) — a sample recorded at time `t` is live while
      `now - t < window_ms`.
    * count-based (`:max_samples`) — only the most recently recorded
      `max_samples` samples per series are retained.

  All timestamps are produced by an injectable `:clock` function so time can be
  controlled deterministically in tests.
  """

  use GenServer

  @default_name Percentile

  ## Public API

  @doc """
  Starts and registers the process.

  ## Options

    * `:name` — the name to register the process under. Default: `Percentile`.
    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Default: `fn -> System.monotonic_time(:millisecond) end`.
    * `:window_ms` — positive integer enabling a time-based window.
    * `:max_samples` — positive integer enabling a count-based window.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records a numeric `value` into series `name`, timestamped with the current
  clock time. Returns `:ok`.
  """
  @spec record(term, number) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  @doc """
  Computes the requested `percentile` (a float in `0.0..1.0`) over the currently
  live samples of series `name`.

  Returns `{:ok, value}` where `value` is one of the recorded samples, or
  `{:error, :empty}` when the series has no live samples.
  """
  @spec query(term, float) :: {:ok, number} | {:error, :empty}
  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @doc """
  Discards all samples for series `name`. Returns `:ok`.
  """
  @spec reset(term) :: :ok
  def reset(name) do
    GenServer.call(@default_name, {:reset, name})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    window_ms = validate_positive(Keyword.get(opts, :window_ms))
    max_samples = validate_positive(Keyword.get(opts, :max_samples))

    state = %{
      clock: clock,
      window_ms: window_ms,
      max_samples: max_samples,
      # series name => list of {timestamp, value}, newest first
      series: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    existing = Map.get(state.series, name, [])
    updated = enforce_max([{now, value} | existing], state.max_samples)
    {:reply, :ok, %{state | series: Map.put(state.series, name, updated)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    now = state.clock.()

    live =
      state.series
      |> Map.get(name, [])
      |> live_samples(now, state.window_ms)
      |> Enum.map(fn {_t, v} -> v end)
      |> Enum.sort()

    {:reply, percentile_of(live, percentile), state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  ## Helpers

  defp validate_positive(nil), do: nil

  defp validate_positive(n) when is_integer(n) and n > 0, do: n

  defp validate_positive(other) do
    raise ArgumentError, "expected a positive integer, got: #{inspect(other)}"
  end

  defp enforce_max(samples, nil), do: samples
  defp enforce_max(samples, max), do: Enum.take(samples, max)

  defp live_samples(samples, _now, nil), do: samples

  defp live_samples(samples, now, window_ms) do
    Enum.filter(samples, fn {t, _v} -> now - t < window_ms end)
  end

  defp percentile_of(sorted, percentile) do
    # TODO
  end
end
```