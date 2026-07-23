# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)

    # Validate up front, in the caller's process, so bad options raise
    # ArgumentError to the caller instead of only crashing the linked child.
    _ = validate_positive(Keyword.fetch!(opts, :half_life_ms), :half_life_ms)
    _ = validate_optional_positive(Keyword.get(opts, :max_samples))

    GenServer.start_link(__MODULE__, opts, name: name)
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

      # The float tolerance must scale WITH the weights: an absolute epsilon
      # dwarfs the whole distribution once a series has aged 30+ half-lives
      # (total < 1.0e-9 yet nonzero), making the first sample win every
      # percentile. Relative to total, the comparison is invariant under
      # uniform aging — the prompt's neutrality rule.
      tolerance = @epsilon * total

      {_cum, value} =
        Enum.reduce_while(sorted, {0.0, nil}, fn {v, w}, {cum, _last} ->
          cum2 = cum + w

          if cum2 >= target - tolerance do
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

## Test harness — implement the `# TODO` test

```elixir
defmodule DecayPercentileTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  setup do
    start_supervised!({Clock, 0})
    :ok
  end

  defp start_server(opts) do
    opts =
      opts
      |> Keyword.put_new(:clock, &Clock.now/0)
      |> Keyword.put_new(:half_life_ms, 1_000)

    start_supervised!({DecayPercentile, opts})
    :ok
  end

  # ---------------------------------------------------------
  # Base nearest-rank behavior when all samples are fresh
  # ---------------------------------------------------------

  test "with equal fresh weights, percentiles match plain nearest-rank" do
    start_server([])
    for v <- 1..100, do: assert(:ok = DecayPercentile.record(:d, v))

    assert {:ok, 50} = DecayPercentile.query(:d, 0.50)
    assert {:ok, 95} = DecayPercentile.query(:d, 0.95)
    assert {:ok, 1} = DecayPercentile.query(:d, 0.0)
    assert {:ok, 100} = DecayPercentile.query(:d, 1.0)
  end

  test "single sample returns that sample for any percentile" do
    start_server([])
    DecayPercentile.record(:one, 42)

    assert {:ok, 42} = DecayPercentile.query(:one, 0.0)
    assert {:ok, 42} = DecayPercentile.query(:one, 0.5)
    assert {:ok, 42} = DecayPercentile.query(:one, 1.0)
  end

  test "unknown series is empty" do
    # TODO
  end

  # ---------------------------------------------------------
  # The defining decay behavior
  # ---------------------------------------------------------

  test "a fresh sample outweighs an old one and shifts the median" do
    start_server([])

    # old, low value at t=0
    DecayPercentile.record(:t, 1)

    # 3 half-lives later: old weight = 0.125, new weight = 1.0
    Clock.advance(3_000)
    DecayPercentile.record(:t, 100)

    # W = 1.125, target for p50 = 0.5625; cumulative at 1 is only 0.125,
    # so the median is pulled all the way up to the fresh sample.
    assert {:ok, 100} = DecayPercentile.query(:t, 0.50)
  end

  test "uniform aging does not change the reported percentile" do
    start_server([])

    DecayPercentile.record(:t, 1)
    DecayPercentile.record(:t, 100)

    # both fresh: nearest-rank median (lower of two) is 1
    assert {:ok, 1} = DecayPercentile.query(:t, 0.50)

    # advance the clock with no new records: both weights scale equally
    Clock.advance(3_000)
    assert {:ok, 1} = DecayPercentile.query(:t, 0.50)
  end

  test "total_weight reflects exponential decay of a single sample" do
    start_server([])
    DecayPercentile.record(:w, 5)

    assert {:ok, w0} = DecayPercentile.total_weight(:w)
    assert_in_delta w0, 1.0, 1.0e-9

    Clock.advance(1_000)
    assert {:ok, w1} = DecayPercentile.total_weight(:w)
    assert_in_delta w1, 0.5, 1.0e-9

    Clock.advance(1_000)
    assert {:ok, w2} = DecayPercentile.total_weight(:w)
    assert_in_delta w2, 0.25, 1.0e-9
  end

  # ---------------------------------------------------------
  # Fully underflowed weights read as empty, not as a stale value
  # ---------------------------------------------------------

  test "series whose weights have all underflowed to zero reports empty" do
    start_server([])

    DecayPercentile.record(:u, 1)
    DecayPercentile.record(:u, 50)
    DecayPercentile.record(:u, 100)

    # 2000 half-lives: every 0.5 ^ (age / half_life) underflows to 0.0, so the
    # series holds samples but carries no weight at all.
    Clock.advance(2_000_000)

    assert {:error, :empty} = DecayPercentile.query(:u, 0.0)
    assert {:error, :empty} = DecayPercentile.query(:u, 0.5)
    assert {:error, :empty} = DecayPercentile.query(:u, 1.0)
    assert {:error, :empty} = DecayPercentile.total_weight(:u)
  end

  test "recording after total underflow makes the series report the fresh sample" do
    start_server([])

    DecayPercentile.record(:u2, 1)
    Clock.advance(2_000_000)
    assert {:error, :empty} = DecayPercentile.query(:u2, 0.5)

    # The fresh sample has weight 1.0 while the underflowed one contributes 0.0,
    # so it alone determines every percentile.
    DecayPercentile.record(:u2, 7)

    assert {:ok, 7} = DecayPercentile.query(:u2, 0.0)
    assert {:ok, 7} = DecayPercentile.query(:u2, 1.0)
    assert {:ok, w} = DecayPercentile.total_weight(:u2)
    assert_in_delta w, 1.0, 1.0e-9
  end

  # ---------------------------------------------------------
  # Bounded memory & housekeeping
  # ---------------------------------------------------------

  test "max_samples bounds retained samples, dropping oldest" do
    start_server(max_samples: 5)
    for v <- 1..10, do: DecayPercentile.record(:c, v)

    # only [6,7,8,9,10] remain; all recorded at t=0 => equal weights
    assert {:ok, 6} = DecayPercentile.query(:c, 0.0)
    assert {:ok, 10} = DecayPercentile.query(:c, 1.0)
    assert {:ok, w} = DecayPercentile.total_weight(:c)
    assert_in_delta w, 5.0, 1.0e-9
  end

  test "reset clears a series" do
    start_server([])
    for v <- 1..10, do: DecayPercentile.record(:r, v)
    assert :ok = DecayPercentile.reset(:r)
    assert {:error, :empty} = DecayPercentile.query(:r, 0.5)
  end

  test "series are independent" do
    start_server([])
    DecayPercentile.record(:a, 1)
    DecayPercentile.record(:b, 999)

    assert {:ok, 1} = DecayPercentile.query(:a, 0.5)
    assert {:ok, 999} = DecayPercentile.query(:b, 0.5)

    DecayPercentile.reset(:a)
    assert {:error, :empty} = DecayPercentile.query(:a, 0.5)
    assert {:ok, 999} = DecayPercentile.query(:b, 0.5)
  end

  test "underflow in one series leaves a freshly recorded series unaffected" do
    start_server([])

    DecayPercentile.record(:old, 1)
    Clock.advance(2_000_000)
    DecayPercentile.record(:new, 42)

    assert {:error, :empty} = DecayPercentile.query(:old, 0.5)
    assert {:error, :empty} = DecayPercentile.total_weight(:old)
    assert {:ok, 42} = DecayPercentile.query(:new, 0.5)
  end

  test "invalid half_life raises" do
    assert_raise ArgumentError, fn ->
      DecayPercentile.start_link(name: :bad, clock: &Clock.now/0, half_life_ms: 0)
    end
  end

  test "extremes stay correct in the small-but-nonzero weight regime" do
    start_server([])

    DecayPercentile.record(:tiny, 1)
    DecayPercentile.record(:tiny, 100)

    # 33 half-lives: each weight is ~1.16e-10 — far below any absolute float
    # tolerance, yet NOT underflowed. Uniform aging is neutral, so the
    # extremes must answer exactly as they did when fresh.
    Clock.advance(33_000)

    assert {:ok, 1} = DecayPercentile.query(:tiny, 0.0)
    assert {:ok, 100} = DecayPercentile.query(:tiny, 1.0)
    assert {:ok, 100} = DecayPercentile.query(:tiny, 0.75)
  end
end
```
