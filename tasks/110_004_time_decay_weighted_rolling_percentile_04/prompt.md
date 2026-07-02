# Fill in the middle: `enforce_max/2`

Implement the private `enforce_max/2` helper for the `DecayPercentile` GenServer.

The function bounds how many samples are retained per series so memory stays
bounded. It is called from `handle_call({:record, ...})` right after a new
`{timestamp, value}` tuple has been **prepended** to the series list, so the list
is ordered newest-first (head = most recent, tail = oldest).

`enforce_max/2` receives that sample list and the configured `max_samples` bound:

- When the bound is `nil` (no limit configured), return the sample list
  unchanged.
- When the bound is a positive integer `max`, keep only the `max` most recent
  samples and drop the oldest ones. Because the list is newest-first, the newest
  samples are at the head, so retaining the first `max` elements keeps the freshest
  ones and discards the oldest.

Complete the module below by replacing the `# TODO` in `enforce_max/2` with a
working implementation. Every other function is already implemented — do not
change them.

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
    sorted = Enum.sort_by(weighted, fn {v, _w} -> v end)
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

  defp enforce_max(samples, max) do
    # TODO
  end

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