# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule RankPercentile do
  use GenServer

  @default_name RankPercentile

  ## Public API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  def rank(name, value) when is_number(value) do
    GenServer.call(@default_name, {:rank, name, value})
  end

  def count_above(name, threshold) when is_number(threshold) do
    GenServer.call(@default_name, {:count_above, name, threshold})
  end

  def reset(name), do: GenServer.call(@default_name, {:reset, name})

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    window_ms = validate_positive(Keyword.get(opts, :window_ms))
    max_samples = validate_positive(Keyword.get(opts, :max_samples))

    {:ok,
     %{
       clock: clock,
       window_ms: window_ms,
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
    sorted = live_values(state, name)
    {:reply, percentile_of(sorted, percentile), state}
  end

  def handle_call({:rank, name, value}, _from, state) do
    sorted = live_values(state, name)

    result =
      case sorted do
        [] -> {:error, :empty}
        _ -> {:ok, Enum.count(sorted, &(&1 <= value)) / length(sorted)}
      end

    {:reply, result, state}
  end

  def handle_call({:count_above, name, threshold}, _from, state) do
    count = state |> live_values(name) |> Enum.count(&(&1 > threshold))
    {:reply, {:ok, count}, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  ## Helpers

  defp live_values(state, name) do
    now = state.clock.()

    state.series
    |> Map.get(name, [])
    |> live_samples(now, state.window_ms)
    |> Enum.map(fn {_t, v} -> v end)
    |> Enum.sort()
  end

  defp percentile_of([], _percentile), do: {:error, :empty}

  defp percentile_of(sorted, percentile) do
    n = length(sorted)
    rank = max(1, ceil(percentile * n))
    {:ok, Enum.at(sorted, rank - 1)}
  end

  defp enforce_max(samples, nil), do: samples
  defp enforce_max(samples, max), do: Enum.take(samples, max)

  defp live_samples(samples, _now, nil), do: samples

  defp live_samples(samples, now, window_ms) do
    Enum.filter(samples, fn {t, _v} -> now - t < window_ms end)
  end

  defp validate_positive(nil), do: nil
  defp validate_positive(n) when is_integer(n) and n > 0, do: n

  defp validate_positive(other) do
    raise ArgumentError, "expected a positive integer, got: #{inspect(other)}"
  end
end
```
