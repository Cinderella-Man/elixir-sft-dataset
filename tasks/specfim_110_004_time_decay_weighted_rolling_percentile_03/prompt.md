# Fill in one @spec

Below: a working module where the `@spec` for
`record/2` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `record/2` missing

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
  # TODO: @spec
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

The `@spec` attribute only — nothing more.
