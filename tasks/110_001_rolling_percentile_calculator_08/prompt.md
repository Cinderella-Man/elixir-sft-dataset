# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `init` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# Rolling Percentile Calculator

Write me an Elixir GenServer module called `Percentile` that maintains rolling
windows of numeric samples and computes percentiles on demand. A single running
process manages many independent **series**, each identified by an arbitrary
`name` term.

## Public API

- `Percentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — the name to register the process under. Default: `Percentile`.
  - `:clock` — a zero-arity function returning the current time in
    milliseconds. Default: `fn -> System.monotonic_time(:millisecond) end`.
    Every timestamp used for window expiration must come from this function so
    that time can be controlled deterministically in tests.
  - `:window_ms` — a positive integer enabling a **time-based** window. A sample
    recorded at time `t` is included in queries as long as `now - t < window_ms`;
    it expires (is excluded) once `now - t >= window_ms`. If omitted, no
    time-based expiration occurs.
  - `:max_samples` — a positive integer enabling a **count-based** window. Only
    the most recently recorded `max_samples` samples per series are retained; when
    a new sample pushes a series over the limit, the oldest sample in that series
    is dropped. If omitted, the sample count is unbounded.

  Both `:window_ms` and `:max_samples` may be supplied together, in which case
  both constraints apply.

- `Percentile.record(name, value)` — records a numeric `value` (integer or float)
  into the series `name`, timestamped with the current clock time. Returns `:ok`.

- `Percentile.query(name, percentile)` — computes the requested percentile over
  the currently-live samples of series `name`. `percentile` is a float in the
  inclusive range `0.0..1.0` (e.g. `0.95` for p95). Returns `{:ok, value}` where
  `value` is one of the recorded samples, or `{:error, :empty}` when the series
  has no live samples (never recorded, fully expired, or reset).

- `Percentile.reset(name)` — discards all samples for series `name`. Returns `:ok`.

The default-registered process name (`Percentile`) is used by `record/2`,
`query/2`, and `reset/1`, so those three functions take only the series `name`,
not a server reference.

## Percentile definition (nearest-rank)

Use the **nearest-rank** method so results are exactly reproducible. Given the
`n` live samples of a series sorted in ascending order as `s_1, s_2, …, s_n`
(1-indexed), for a percentile `p`:

```
rank  = max(1, ceil(p * n))
value = s_rank
```

Consequences you must satisfy:
- `p = 0.0` returns the minimum live sample.
- `p = 1.0` returns the maximum live sample.
- For samples `1..100`, `query(name, 0.50)` returns `50`, `0.95` returns `95`,
  and `0.99` returns `99`.

## Window semantics

- Series are fully independent: recording, querying, or resetting one series must
  never affect another.
- Time-based expiration must be applied at query time (so advancing the clock and
  then querying reflects the newly-expired samples), and expired samples must not
  contribute to the count `n` used in the nearest-rank computation.
- A series whose samples have all expired must report `{:error, :empty}`.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies (no t-digest libraries; a sorted list or similar is fine).

## The module with `init` missing

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

  def init(opts) do
    # TODO
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

  defp percentile_of([], _percentile), do: {:error, :empty}

  defp percentile_of(sorted, percentile) do
    n = length(sorted)
    rank = max(1, ceil(percentile * n))
    {:ok, Enum.at(sorted, rank - 1)}
  end
end
```

Reply with `init` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
