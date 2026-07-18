# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Time-Decay Weighted Rolling Percentile

Write me an Elixir GenServer module called `DecayPercentile` that computes
percentiles over samples whose influence **fades continuously with age** rather
than dropping off a hard window edge. A single running process manages many
independent **series**, each identified by an arbitrary `name` term.

Instead of a live/expired boolean, every sample carries an exponentially-decaying
weight based on how long ago it was recorded. Recent samples dominate; old
samples still count, but progressively less. This gives smooth, drift-aware
percentiles with no abrupt jumps when a sample crosses a boundary.

## Public API

- `DecayPercentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — name to register under. Default: `DecayPercentile`.
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Default: `fn -> System.monotonic_time(:millisecond) end`. All ages are
    computed from this clock.
  - `:half_life_ms` — **required** positive integer. A sample of age `a` has
    weight `0.5 ^ (a / half_life_ms)` (weight `1.0` when just recorded, `0.5` at
    one half-life, `0.25` at two, and so on). Anything else raises `ArgumentError`.
  - `:max_samples` — optional positive integer bounding retained samples per
    series (oldest dropped first) so memory stays bounded.

- The `name` argument of `record/2`, `query/2`, `total_weight/1`, and `reset/1` is purely the **series** name — these helpers always call the server registered under the default `DecayPercentile` name (the `:name` start option changes process registration only, not how the helpers address the server).
- `DecayPercentile.record(name, value)` — records a numeric `value`, timestamped
  with the current clock time. Returns `:ok`.

- `DecayPercentile.query(name, percentile)` — computes the **weighted nearest-rank**
  percentile over the current samples of series `name`. `percentile` is a float in
  `0.0..1.0`. Returns `{:ok, value}` where `value` is one of the recorded samples,
  or `{:error, :empty}` when the series has no samples (or all weights have
  underflowed to zero). A sample whose weight has underflowed to zero is
  excluded from selection entirely — it can never be the returned value, at
  any percentile.

- `DecayPercentile.total_weight(name)` — returns `{:ok, w}` where `w` is the sum
  of the current decayed weights (a float), or `{:error, :empty}` under the same
  emptiness rule as `query` (no samples, or every weight underflowed to zero —
  never `{:ok, 0.0}`). Useful as an "effective sample count" for inspection.

- `DecayPercentile.reset(name)` — discards all samples for series `name`.
  Returns `:ok`.

## Weighted nearest-rank definition

At query time compute each sample's weight `w_i = 0.5 ^ ((now - t_i)/half_life_ms)`.
Sort the samples ascending by **value** as `(v_1, w_1), …, (v_n, w_n)` and let
`W = Σ w_i`. For a percentile `p`, walk the sorted list accumulating weight and
return the value `v_j` at the first position where the cumulative weight reaches
`p * W`:

```
target = p * W
return the first v_j where (w_1 + … + w_j) >= target
```

Consequences:
- `p = 0.0` returns the minimum-valued sample; `p = 1.0` returns the maximum.
- Doubling a sample's freshness (halving its age relative to others) can move the
  reported percentile toward that sample's value.
- **Uniform aging is neutral**: if no new samples arrive, advancing the clock
  scales every weight by the same factor, so the reported percentile is unchanged.

## Semantics

- Series are fully independent.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies. `:math.pow/2` is fine for the decay factor.

## The module with `start_link` missing

```elixir
defmodule DecayPercentile do
  @moduledoc """
  A GenServer that computes percentiles over samples whose influence decays
  exponentially with age. Each sample of age `a` has weight
  `0.5 ^ (a / half_life_ms)`, so recent samples dominate while old samples fade
  smoothly instead of dropping off a hard window edge.

  Percentiles use a weighted nearest-rank: samples are sorted by value and the
  first value whose cumulative weight reaches `p * total_weight` is returned.
  """

  use GenServer

  @default_name DecayPercentile
  @epsilon 1.0e-9

  ## Public API

  def start_link(opts \\ []) do
    # TODO
  end

  @doc "Records `value` into the time-decay rolling percentile for `name`. Returns `:ok`."
  @spec record(term, number) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  @spec query(term, float) :: {:ok, number} | {:error, :empty}
  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @spec total_weight(term) :: {:ok, float} | {:error, :empty}
  def total_weight(name), do: GenServer.call(@default_name, {:total_weight, name})

  @spec reset(term) :: :ok
  def reset(name), do: GenServer.call(@default_name, {:reset, name})

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    half_life = validate_positive(Keyword.fetch!(opts, :half_life_ms), :half_life_ms)
    max_samples = validate_optional_positive(Keyword.get(opts, :max_samples))

    {:ok,
     %{
       clock: clock,
       half_life: half_life,
       max_samples: max_samples,
       series: %{}
     }}
  end

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    existing = Map.get(state.series, name, [])
    updated = enforce_max([{now, value} | existing], state.max_samples)
    {:reply, :ok, %{state | series: Map.put(state.series, name, updated)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    weighted = weighted_samples(state, name)
    {:reply, weighted_rank(weighted, percentile), state}
  end

  def handle_call({:total_weight, name}, _from, state) do
    weighted = weighted_samples(state, name)
    w = Enum.reduce(weighted, 0.0, fn {_v, w}, acc -> acc + w end)
    result = if weighted == [] or w == 0.0, do: {:error, :empty}, else: {:ok, w}
    {:reply, result, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  ## Helpers

  defp weighted_samples(state, name) do
    now = state.clock.()

    state.series
    |> Map.get(name, [])
    |> Enum.map(fn {t, v} ->
      age = now - t
      {v, :math.pow(0.5, age / state.half_life)}
    end)
  end

  defp weighted_rank(weighted, percentile) do
    # A sample whose weight has underflowed to exactly 0.0 contributes nothing
    # and must not be selectable — the same absence rule that makes an
    # all-underflowed series {:error, :empty} (a zero-weight sample would
    # otherwise win percentile 0.0, since 0.0 >= a target of 0.0).
    sorted =
      weighted
      |> Enum.reject(fn {_v, w} -> w == 0.0 end)
      |> Enum.sort_by(fn {v, _w} -> v end)

    total = Enum.reduce(sorted, 0.0, fn {_v, w}, acc -> acc + w end)

    if sorted == [] or total == 0.0 do
      {:error, :empty}
    else
      target = percentile * total

      {_cum, value} =
        Enum.reduce_while(sorted, {0.0, nil}, fn {v, w}, {cum, _last} ->
          cum2 = cum + w

          if cum2 >= target - @epsilon do
            {:halt, {cum2, v}}
          else
            {:cont, {cum2, v}}
          end
        end)

      {:ok, value}
    end
  end

  defp enforce_max(samples, nil), do: samples
  defp enforce_max(samples, max), do: Enum.take(samples, max)

  defp validate_positive(n, _name) when is_integer(n) and n > 0, do: n

  defp validate_positive(other, name) do
    raise ArgumentError, "#{inspect(name)} must be a positive integer, got: #{inspect(other)}"
  end

  defp validate_optional_positive(nil), do: nil
  defp validate_optional_positive(n) when is_integer(n) and n > 0, do: n

  defp validate_optional_positive(other) do
    raise ArgumentError, ":max_samples must be a positive integer, got: #{inspect(other)}"
  end
end
```

Give me only the complete implementation of `start_link` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
