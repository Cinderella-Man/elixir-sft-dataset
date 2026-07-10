# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

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

  @doc "Pushes `value` into the streaming percentile for `name`. Returns `:ok`."
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

## Test harness — implement the `# TODO` test

```elixir
defmodule StreamingPercentileTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = StreamingPercentile.start_link([])
    %{sp: pid}
  end

  defp close_to(a, b, eps \\ 1.0e-9), do: abs(a - b) <= eps

  # -------------------------------------------------------
  # No-data behavior
  # -------------------------------------------------------

  test "percentile on empty stream returns :no_data", %{sp: s} do
    assert {:error, :no_data} = StreamingPercentile.percentile(s, "x", 0.5)
    assert {:error, :no_data} = StreamingPercentile.percentiles(s, "x", [0.5, 0.95])
    assert {:error, :no_data} = StreamingPercentile.window(s, "x")
  end

  # -------------------------------------------------------
  # Validation
  # -------------------------------------------------------

  test "percentile rejects out-of-range q", %{sp: s} do
    StreamingPercentile.push(s, "a", 10, 5)

    assert {:error, :invalid_quantile} = StreamingPercentile.percentile(s, "a", -0.1)
    assert {:error, :invalid_quantile} = StreamingPercentile.percentile(s, "a", 1.1)
  end

  test "percentiles rejects if any q is out of range", %{sp: s} do
    StreamingPercentile.push(s, "a", 10, 5)

    assert {:error, :invalid_quantile} =
             StreamingPercentile.percentiles(s, "a", [0.5, 2.0])
  end

  test "push rejects non-numeric values and non-positive window sizes", %{sp: s} do
    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", :not_number, 10)
    end

    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", 10, 0)
    end

    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", 10, -1)
    end
  end

  # -------------------------------------------------------
  # Basic quantile math
  # -------------------------------------------------------

  test "single-value window returns that value for any q", %{sp: s} do
    StreamingPercentile.push(s, "a", 42, 10)

    for q <- [0.0, 0.25, 0.5, 0.75, 1.0] do
      {:ok, v} = StreamingPercentile.percentile(s, "a", q)
      assert v == 42.0
    end
  end

  test "q=0 and q=1 return min and max", %{sp: s} do
    for v <- [10, 30, 20, 50, 40], do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, min} = StreamingPercentile.percentile(s, "a", 0.0)
    {:ok, max} = StreamingPercentile.percentile(s, "a", 1.0)

    assert min == 10.0
    assert max == 50.0
  end

  test "median of odd-length sorted stream is the middle element", %{sp: s} do
    for v <- [10, 20, 30, 40, 50], do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert med == 30.0
  end

  test "median of even-length stream linearly interpolates", %{sp: s} do
    for v <- [10, 20, 30, 40], do: StreamingPercentile.push(s, "a", v, 4)

    # sorted = [10, 20, 30, 40], N=4, rank = 0.5 * 3 = 1.5
    # lo=1, hi=2, frac=0.5, result = 20 + 0.5*(30-20) = 25
    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert close_to(med, 25.0)
  end

  test "percentile between ranks uses linear interpolation", %{sp: s} do
    # TODO
  end

  # -------------------------------------------------------
  # Batch query
  # -------------------------------------------------------

  test "percentiles/3 returns a map of q -> value", %{sp: s} do
    for v <- 1..100, do: StreamingPercentile.push(s, "a", v, 100)

    {:ok, results} = StreamingPercentile.percentiles(s, "a", [0.5, 0.95, 0.99])

    # With 100 values (1..100), N=100, rank(q) = q * 99.
    # p50: rank 49.5 → sorted[49]=50, sorted[50]=51, frac=0.5 → 50.5
    # p95: rank 94.05 → sorted[94]=95, sorted[95]=96, frac=0.05 → 95.05
    # p99: rank 98.01 → sorted[98]=99, sorted[99]=100, frac=0.01 → 99.01
    assert close_to(results[0.5], 50.5)
    assert close_to(results[0.95], 95.05)
    assert close_to(results[0.99], 99.01)
  end

  test "percentiles/3 on a single-value window returns same value for every q", %{sp: s} do
    StreamingPercentile.push(s, "a", 7.5, 3)

    {:ok, results} = StreamingPercentile.percentiles(s, "a", [0.0, 0.5, 0.99])

    for q <- [0.0, 0.5, 0.99], do: assert(results[q] == 7.5)
  end

  # -------------------------------------------------------
  # Sliding window behavior
  # -------------------------------------------------------

  test "window bounded to window_size — oldest values drop off", %{sp: s} do
    # Fill with 10 values at window=5 — only last 5 should remain
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, current} = StreamingPercentile.window(s, "a")
    assert current == [6.0, 7.0, 8.0, 9.0, 10.0]
  end

  test "quantile is computed over current window only, not full history", %{sp: s} do
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 3)

    {:ok, current} = StreamingPercentile.window(s, "a")
    assert current == [8.0, 9.0, 10.0]

    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert med == 9.0
  end

  # -------------------------------------------------------
  # window_size growth (max_window_size semantics)
  # -------------------------------------------------------

  test "window_size grows with largest-ever request and never shrinks", %{sp: s} do
    # Push with window=3
    for v <- 1..5, do: StreamingPercentile.push(s, "a", v, 3)

    {:ok, w1} = StreamingPercentile.window(s, "a")
    assert length(w1) == 3

    # Push with window=10 — max_window_size grows
    for v <- 6..10, do: StreamingPercentile.push(s, "a", v, 10)

    {:ok, w2} = StreamingPercentile.window(s, "a")
    # We retained 3 then grew to 10 and pushed 5 more → length 8
    assert length(w2) == 8

    # Push with window=2 (smaller) — max_window_size does NOT shrink
    StreamingPercentile.push(s, "a", 11, 2)
    {:ok, w3} = StreamingPercentile.window(s, "a")
    # max remained 10, so length caps at 10 as we add more
    assert length(w3) == 9

    # max_window_size is internal and deliberately not inspected. Verify it
    # through the documented window/2 API instead: with the retention bound
    # still at 10, further pushes with a smaller requested window keep growing
    # the window up to exactly 10 and then cap there (it would cap at 2 if the
    # bound had shrunk).
    StreamingPercentile.push(s, "a", 12, 2)
    StreamingPercentile.push(s, "a", 13, 2)

    {:ok, w4} = StreamingPercentile.window(s, "a")
    assert length(w4) == 10

    StreamingPercentile.push(s, "a", 14, 2)

    {:ok, w5} = StreamingPercentile.window(s, "a")
    assert w5 == Enum.map(5..14, &(&1 * 1.0))
    assert Process.alive?(s)
  end

  # -------------------------------------------------------
  # Stream independence
  # -------------------------------------------------------

  test "different stream names are independent", %{sp: s} do
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 10)
    for v <- 100..110, do: StreamingPercentile.push(s, "b", v, 11)

    {:ok, a_med} = StreamingPercentile.percentile(s, "a", 0.5)
    {:ok, b_med} = StreamingPercentile.percentile(s, "b", 0.5)

    assert close_to(a_med, 5.5)
    assert close_to(b_med, 105.0)

    # Pushing to "a" doesn't affect "b"
    StreamingPercentile.push(s, "a", 99999, 10)
    {:ok, b_med_again} = StreamingPercentile.percentile(s, "b", 0.5)
    assert close_to(b_med, b_med_again)
  end

  # -------------------------------------------------------
  # Duplicate values
  # -------------------------------------------------------

  test "quantiles handle duplicate values correctly", %{sp: s} do
    for _ <- 1..10, do: StreamingPercentile.push(s, "a", 7.0, 10)

    for q <- [0.0, 0.25, 0.5, 0.75, 0.95, 1.0] do
      {:ok, v} = StreamingPercentile.percentile(s, "a", q)
      assert v == 7.0
    end
  end
end
```
