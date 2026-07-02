# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir GenServer module called `StreamingPercentile` that maintains multiple named numeric streams and computes **percentile queries** (p50, p95, p99, or any arbitrary quantile) over a sliding count-based window.

Instead of computing a single mean, this module answers quantile queries. The window is count-based — "the last N pushed values per stream" — and the quantile is computed via linear interpolation between the two nearest ranks (the same method used by most statistics libraries and databases).

I need these functions in the public API:

- `StreamingPercentile.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `StreamingPercentile.push(server, name, value, window_size)` which appends a numeric value to the named stream's sliding window. `window_size` is the maximum number of values retained for that stream (positive integer). If `window_size` changes on subsequent pushes for the same stream, use the **largest window_size ever seen** for that stream as the effective retention bound — matching the pattern from MovingAverage where `max_period` grows over time and never shrinks. Returns `:ok`.

- `StreamingPercentile.percentile(server, name, q)` where `q` is a float in `[0.0, 1.0]` (e.g. `0.5` for the median, `0.95` for p95). Returns `{:ok, float}` or `{:error, :no_data}` if no values have been pushed yet.

- `StreamingPercentile.percentiles(server, name, q_list)` — batch form, computes multiple percentiles in a single call. `q_list` is a non-empty list of floats in `[0.0, 1.0]`. Returns `{:ok, %{q => float}}` mapping each input `q` to its result, or `{:error, :no_data}`. This matters for performance: sorting is done once and all quantiles are computed against the same sorted snapshot.

- `StreamingPercentile.window(server, name)` — inspection helper returning `{:ok, [float]}` with the current window contents in insertion order (oldest → newest), or `{:error, :no_data}`. Useful for debugging and tests.

**Quantile algorithm.** For a sorted window of N values (smallest first) and a quantile `q`:

1. If N == 1, return the single value.
2. Compute `rank = q * (N - 1)` (floating point, in `[0, N-1]`).
3. Let `lo = floor(rank)` and `hi = ceil(rank)`.
4. If `lo == hi`, return `sorted[lo]` exactly.
5. Otherwise, interpolate: `sorted[lo] + (rank - lo) * (sorted[hi] - sorted[lo])`.

This is the linear-interpolation method (NumPy's default `method="linear"`, Excel's PERCENTILE.INC). Edge cases: `q = 0.0` returns the minimum; `q = 1.0` returns the maximum.

**Internal representation.** The window is maintained as a plain list of values in **insertion order**, newest-first, bounded by the current `max_window_size`. On each `push/4`:

1. Prepend the new value.
2. Trim to at most `max_window_size` entries.

At query time (`percentile/3` or `percentiles/3`):

1. Snapshot-sort the current window into ascending order.
2. Evaluate the quantile formula above (once per `q` in the batch form, but only one sort total).

Sorting on every query is O(N log N). This is the intended implementation — a more sophisticated skip-list or order-statistics tree would be out of scope. What matters is that the quantile semantics are correct, especially around interpolation and edge cases.

**Validation.**

- `push/4` with non-numeric `value` or non-positive `window_size` raises `FunctionClauseError`.
- `percentile/3` with `q` outside `[0.0, 1.0]` returns `{:error, :invalid_quantile}`.
- `percentiles/3` with any `q` outside `[0.0, 1.0]` returns `{:error, :invalid_quantile}` — no partial results.

Different stream names are completely independent.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Module under test

```elixir
defmodule StreamingPercentile do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams as sliding
  count-based windows and answers arbitrary-quantile queries via linear
  interpolation between the two nearest ranks.

  ## Quantile definition

  For a sorted window `s` of `N` values (ascending) and a quantile `q` in
  `[0.0, 1.0]`:

      rank = q * (N - 1)
      lo   = floor(rank);  hi = ceil(rank)
      lo == hi -> sorted[lo]
      else     -> sorted[lo] + (rank - lo) * (sorted[hi] - sorted[lo])

  This is the linear-interpolation method — NumPy's default `"linear"`,
  Excel's `PERCENTILE.INC`, the method described by Hyndman & Fan (1996)
  as type 7.

  ## State layout

      %{
        streams: %{
          stream_name => %{
            values:           [float],  # newest-first, bounded by max_window_size
            max_window_size:  pos_integer
          }
        }
      }

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec push(GenServer.server(), term(), number(), pos_integer()) :: :ok
  def push(server, name, value, window_size)
      when is_number(value) and is_integer(window_size) and window_size > 0 do
    GenServer.call(server, {:push, name, value, window_size})
  end

  @spec percentile(GenServer.server(), term(), float()) ::
          {:ok, float()} | {:error, :no_data | :invalid_quantile}
  def percentile(server, name, q) when is_float(q) or is_integer(q) do
    if valid_quantile?(q) do
      GenServer.call(server, {:percentile, name, q * 1.0})
    else
      {:error, :invalid_quantile}
    end
  end

  @spec percentiles(GenServer.server(), term(), [float(), ...]) ::
          {:ok, %{float() => float()}} | {:error, :no_data | :invalid_quantile}
  def percentiles(server, name, [_ | _] = q_list) do
    if Enum.all?(q_list, &valid_quantile?/1) do
      GenServer.call(server, {:percentiles, name, Enum.map(q_list, &(&1 * 1.0))})
    else
      {:error, :invalid_quantile}
    end
  end

  @spec window(GenServer.server(), term()) ::
          {:ok, [float()]} | {:error, :no_data}
  def window(server, name), do: GenServer.call(server, {:window, name})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok), do: {:ok, %{streams: %{}}}

  @impl GenServer
  def handle_call({:push, name, value, window_size}, _from, state) do
    stream = stream_for(state, name)

    new_max = max(stream.max_window_size, window_size)
    new_values = [value * 1.0 | stream.values] |> Enum.take(new_max)

    new_stream = %{stream | values: new_values, max_window_size: new_max}
    {:reply, :ok, put_stream(state, name, new_stream)}
  end

  def handle_call({:percentile, name, q}, _from, state) do
    stream = stream_for(state, name)

    if stream.values == [] do
      {:reply, {:error, :no_data}, state}
    else
      sorted = Enum.sort(stream.values)
      {:reply, {:ok, quantile(sorted, q)}, state}
    end
  end

  def handle_call({:percentiles, name, q_list}, _from, state) do
    stream = stream_for(state, name)

    if stream.values == [] do
      {:reply, {:error, :no_data}, state}
    else
      sorted = Enum.sort(stream.values)
      results = Map.new(q_list, fn q -> {q, quantile(sorted, q)} end)
      {:reply, {:ok, results}, state}
    end
  end

  def handle_call({:window, name}, _from, state) do
    stream = stream_for(state, name)

    if stream.values == [] do
      {:reply, {:error, :no_data}, state}
    else
      # Return in insertion order (oldest → newest).
      {:reply, {:ok, Enum.reverse(stream.values)}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Quantile math — operates on an already-sorted ascending list
  # ---------------------------------------------------------------------------

  defp quantile([only], _q), do: only

  defp quantile(sorted, q) do
    n = length(sorted)
    rank = q * (n - 1)

    lo_idx = trunc(rank)
    hi_idx = min(lo_idx + 1, n - 1)

    lo_val = Enum.at(sorted, lo_idx)

    if lo_idx == hi_idx do
      lo_val
    else
      hi_val = Enum.at(sorted, hi_idx)
      frac = rank - lo_idx
      lo_val + frac * (hi_val - lo_val)
    end
  end

  # ---------------------------------------------------------------------------
  # Stream helpers
  # ---------------------------------------------------------------------------

  defp stream_for(state, name),
    do: Map.get(state.streams, name, new_stream())

  defp put_stream(state, name, stream),
    do: %{state | streams: Map.put(state.streams, name, stream)}

  defp new_stream, do: %{values: [], max_window_size: 0}

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp valid_quantile?(q) when is_number(q), do: q >= 0.0 and q <= 1.0
  defp valid_quantile?(_), do: false
end
```
