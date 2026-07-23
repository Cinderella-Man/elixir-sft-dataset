# Cover this module with tests

Here is a finished Elixir module together with the specification it was
written against. Your job is the harness: write an ExUnit suite that would
catch a wrong implementation of this module.

What the harness must satisfy:
- Name the test module `<Module>Test` and `use ExUnit.Case, async: false`.
- Skip `ExUnit.start()` — the evaluator calls it.
- Keep everything inline: fakes, clock Agents, helpers — the file must stand
  alone.
- Work through the whole public API, including the edge cases the
  specification calls out.
- Zero compile warnings (prefix unused variables with `_`; match float zero
  as `+0.0`/`-0.0`).
- Deliver the complete harness as one file.

## Original specification

# Histogram-Based Approximate Rolling Percentile

Write me an Elixir GenServer module called `HistogramPercentile` that estimates
percentiles over a rolling time window using a **fixed bucket histogram** instead
of storing every raw sample. A single running process manages many independent
**series**, each identified by an arbitrary `name` term.

Unlike a sorted-list calculator, this variant trades exactness for **bounded
memory**: no matter how many samples arrive, a series only ever stores a small
grid of per-time-slice bucket counts.

## Public API

- `HistogramPercentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — the name to register under. Default: `HistogramPercentile`.
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Default: `fn -> System.monotonic_time(:millisecond) end`. Every timestamp used
    for windowing must come from this function.
  - `:edges` — **required**. A strictly increasing list of at least two numbers
    `[e0, e1, …, ek]` defining `k` buckets. Bucket `i` covers `[e_i, e_{i+1})`,
    with the final bucket `[e_{k-1}, ek]` treated as closed. A recorded value below
    `e0` is clamped into bucket 0; a value at or above `ek` is clamped into the last
    bucket. Supplying anything else raises `ArgumentError` — and the raise comes
    **synchronously from `start_link/1` in the calling process**: validate the
    options eagerly before spawning the server, rather than raising inside
    `init/1`, which would turn the error into a linked-process exit instead of a
    catchable raise.
  - `:window_ms` — **required** positive integer. A sample recorded at time `t`
    contributes to queries while `now - t < window_ms`.
  - `:slots` — positive integer, default `60`. The window is divided into this many
    time slices; each series keeps one histogram per slice in a ring buffer. When a
    slice's slot is reused in a later cycle, its old counts are discarded. Slot
    reuse is **not** the only expiry: each slot must remember which time slice
    wrote it, because a query must exclude any slot whose slice has already aged
    out of the window — even when that slot has not been reused yet. Once
    `window_ms` passes with no new samples recorded, a query on that series
    returns `{:error, :empty}`.

- `HistogramPercentile.record(series, value)` — increments the bucket for `value`
  in the current time slice of series `series`. Returns `:ok`.

- `HistogramPercentile.query(series, percentile)` — returns `{:ok, estimate}` where
  `estimate` is a float, or `{:error, :empty}` when no live counts exist.
  `percentile` is a float in `0.0..1.0`.

- `HistogramPercentile.reset(series)` — discards all counts for series `series`.
  Returns `:ok`.

These three functions are always addressed to the singleton process registered
under the **default** `HistogramPercentile` name — their first argument is a
**series identifier** (an arbitrary term such as `:latency` or `:d`), never a
server reference or pid. Do not thread a server argument through the API.

## Estimation algorithm (histogram quantile)

At query time, sum the per-bucket counts across every stored slice whose start
time `s` satisfies `now - s < window_ms`, producing a list of counts
`c_0 … c_{k-1}` with total `n`. If `n == 0`, return `{:error, :empty}`. Otherwise
use Prometheus-style linear interpolation:

```
target = percentile * n
walk buckets in order, tracking cum_before (counts in earlier buckets);
pick the first bucket i where cum_before + c_i >= target (or the last bucket);
lo = e_i,  hi = e_{i+1},  frac = (target - cum_before) / c_i  (0 if c_i == 0)
estimate = lo + (hi - lo) * clamp(frac, 0.0, 1.0)
```

Consequences:
- `percentile = 0.0` returns `e0` (the low edge).
- `percentile = 1.0` returns the high edge of the highest OCCUPIED bucket (that is what the interpolation above yields — e.g. `e1` when only bucket 0 holds counts; it equals `ek` only when the last bucket is occupied).
- Results are approximate; error is bounded by bucket width.

## Semantics

- Series are fully independent.
- Windowing is applied at query time, so advancing the clock and re-querying
  reflects newly-expired slices.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies.

## Module under test

```elixir
defmodule HistogramPercentile do
  @moduledoc """
  A GenServer that estimates percentiles over a rolling time window using a
  fixed bucket histogram, trading exactness for bounded memory.

  Each series stores a ring buffer of `:slots` per-time-slice histograms; every
  histogram is a map of `bucket_index => count`. Percentiles are estimated with
  Prometheus-style linear interpolation across the live buckets.
  """

  use GenServer

  @default_name HistogramPercentile

  ## Public API

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)

    # Validate eagerly in the caller process. If we let `init/1` raise instead,
    # the freshly-spawned (and linked) GenServer would exit with a non-normal
    # reason and take the caller down with it, rather than surfacing a clean
    # ArgumentError.
    _ = validate_edges(Keyword.get(opts, :edges))
    _ = validate_positive(Keyword.fetch!(opts, :window_ms), :window_ms)
    _ = validate_positive(Keyword.get(opts, :slots, 60), :slots)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Records `value` into the rolling histogram for `name`. Returns `:ok`."
  @spec record(term, number) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  @spec query(term, float) :: {:ok, float} | {:error, :empty}
  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @spec reset(term) :: :ok
  def reset(name), do: GenServer.call(@default_name, {:reset, name})

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    edges = validate_edges(Keyword.get(opts, :edges))
    window_ms = validate_positive(Keyword.fetch!(opts, :window_ms), :window_ms)
    slots = validate_positive(Keyword.get(opts, :slots, 60), :slots)
    slice_ms = max(1, div(window_ms + slots - 1, slots))

    {:ok,
     %{
       clock: clock,
       edges: edges,
       edges_t: List.to_tuple(edges),
       bucket_count: length(edges) - 1,
       window_ms: window_ms,
       slots: slots,
       slice_ms: slice_ms,
       series: %{}
     }}
  end

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    slice_index = div(now, state.slice_ms)
    slice_start = slice_index * state.slice_ms
    slot = rem(slice_index, state.slots)

    series = Map.get(state.series, name, %{})

    counts =
      case Map.get(series, slot) do
        {^slice_start, c} -> c
        _ -> %{}
      end

    bucket = bucket_index(value, state.edges_t, state.bucket_count)
    counts = Map.update(counts, bucket, 1, &(&1 + 1))
    series = Map.put(series, slot, {slice_start, counts})

    {:reply, :ok, %{state | series: Map.put(state.series, name, series)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    now = state.clock.()

    merged =
      state.series
      |> Map.get(name, %{})
      |> Map.values()
      |> Enum.filter(fn {slice_start, _} -> now - slice_start < state.window_ms end)
      |> Enum.reduce(%{}, fn {_s, c}, acc -> merge_counts(acc, c) end)

    result = quantile(merged, state.edges_t, state.bucket_count, percentile)
    {:reply, result, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  ## Helpers

  defp quantile(counts, edges_t, k, percentile) do
    list = for i <- 0..(k - 1), do: Map.get(counts, i, 0)
    n = Enum.sum(list)

    if n == 0 do
      {:error, :empty}
    else
      target = percentile * n

      {value, _} =
        Enum.reduce_while(0..(k - 1), {nil, 0}, fn i, {_last, cum_before} ->
          c = Enum.at(list, i)
          cum = cum_before + c

          if cum >= target or i == k - 1 do
            lo = elem(edges_t, i)
            hi = elem(edges_t, i + 1)
            frac = if c == 0, do: 0.0, else: (target - cum_before) / c
            frac = frac |> max(0.0) |> min(1.0)
            {:halt, {lo + (hi - lo) * frac, cum}}
          else
            {:cont, {nil, cum}}
          end
        end)

      {:ok, value * 1.0}
    end
  end

  defp bucket_index(value, edges_t, k) do
    lo = elem(edges_t, 0)
    hi = elem(edges_t, k)
    v = value |> max(lo) |> min(hi)

    Enum.reduce_while(0..(k - 1), k - 1, fn i, _acc ->
      upper = elem(edges_t, i + 1)
      if v < upper, do: {:halt, i}, else: {:cont, min(i + 1, k - 1)}
    end)
  end

  defp merge_counts(acc, c), do: Map.merge(acc, c, fn _k, a, b -> a + b end)

  defp validate_edges(edges) when is_list(edges) and length(edges) >= 2 do
    numbers? = Enum.all?(edges, &is_number/1)

    increasing? =
      edges
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [a, b] -> b > a end)

    if numbers? and increasing? do
      edges
    else
      raise ArgumentError,
            ":edges must be a strictly increasing list of numbers, got: #{inspect(edges)}"
    end
  end

  defp validate_edges(other) do
    raise ArgumentError,
          ":edges must be a strictly increasing list of >= 2 numbers, got: #{inspect(other)}"
  end

  defp validate_positive(n, _name) when is_integer(n) and n > 0, do: n

  defp validate_positive(other, name) do
    raise ArgumentError, "#{inspect(name)} must be a positive integer, got: #{inspect(other)}"
  end
end
```
