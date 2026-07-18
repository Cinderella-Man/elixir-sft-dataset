# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule HistogramPercentile do
  use GenServer

  @default_name HistogramPercentile

  ## Public API

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

  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

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
