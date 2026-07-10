# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule WeightedMovingAverage do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams and computes
  Weighted Moving Average (WMA) and Hull Moving Average (HMA) on demand.

  ## WMA

  Linear weights over the last `period` values, newest weighted `N`:

      WMA = sum(weight_i * v_i) / sum(weight_i)

  where `weight_i = period - i` for `i` in `0..period-1` with `v_0` the
  newest value.  Cold-start (fewer values than `period`): compute WMA over
  all available values using adjusted weights.

  ## HMA

  For period P:

      wma1 = WMA(P / 2)
      wma2 = WMA(P)
      raw  = 2 * wma1 - wma2
      hma  = WMA(raw_series, round(sqrt(P)))

  HMA is maintained incrementally: every push recomputes `raw` and appends
  it to a per-(stream, period) rolling buffer bounded at `round(sqrt(P))`.

  ## State layout

      %{
        streams: %{
          stream_name => %{
            values:     [float],         # newest-first, bounded by max_period
            max_period: non_neg_integer,
            hma:        %{period => %{raw_buffer :: [float]}}
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

  @doc "Pushes `value` into the weighted moving average for `name`. Returns `:ok`."
  @spec push(GenServer.server(), term(), number()) :: :ok
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @spec get(GenServer.server(), term(), :wma | :hma, pos_integer()) ::
          {:ok, float()} | {:error, :no_data | :insufficient_data}
  def get(server, name, type, period)
      when type in [:wma, :hma] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok), do: {:ok, %{streams: %{}}}

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream =
      state
      |> stream_for(name)
      |> push_value(value)

    {:reply, :ok, put_stream(state, name, stream)}
  end

  def handle_call({:get, name, :wma, period}, _from, state) do
    stream = stream_for(state, name)

    if stream.values == [] do
      {:reply, {:error, :no_data}, state}
    else
      stream = maybe_grow_max_period(stream, period)
      stream = trim_values(stream)
      {:reply, {:ok, compute_wma(stream.values, period)}, put_stream(state, name, stream)}
    end
  end

  def handle_call({:get, name, :hma, period}, _from, state) do
    stream = stream_for(state, name)

    cond do
      stream.values == [] ->
        {:reply, {:error, :no_data}, state}

      length(stream.values) < period ->
        {:reply, {:error, :insufficient_data}, state}

      true ->
        {result, stream} = compute_hma(stream, period)
        {:reply, {:ok, result}, put_stream(state, name, stream)}
    end
  end

  # ---------------------------------------------------------------------------
  # Stream bookkeeping
  # ---------------------------------------------------------------------------

  defp stream_for(state, name), do: Map.get(state.streams, name, new_stream())

  defp put_stream(state, name, stream),
    do: %{state | streams: Map.put(state.streams, name, stream)}

  defp new_stream do
    %{
      # newest-first
      values: [],
      max_period: 0,
      # %{period => %{raw_buffer: [float]}}
      hma: %{}
    }
  end

  # ---------------------------------------------------------------------------
  # push_value/2
  #
  # Appends the value to `values`, then for every registered HMA period
  # recomputes `raw` and appends it to that period's raw_buffer.
  #
  # We deliberately do NOT trim `values` here — trimming is deferred until a
  # `:wma` or `:hma` get observes the current max_period.
  # ---------------------------------------------------------------------------

  defp push_value(stream, value) do
    value = value * 1.0
    new_values = [value | stream.values]

    new_hma =
      Map.new(stream.hma, fn {period, hma_state} ->
        wma1_period = div(period, 2)
        wma2_period = period

        # Use the NEW values list (includes this push).
        wma1 = compute_wma(new_values, wma1_period)
        wma2 = compute_wma(new_values, wma2_period)
        raw = 2 * wma1 - wma2

        buffer_size = round(:math.sqrt(period))
        new_buffer = [raw | hma_state.raw_buffer] |> Enum.take(buffer_size)

        {period, %{hma_state | raw_buffer: new_buffer}}
      end)

    %{stream | values: new_values, hma: new_hma}
  end

  # ---------------------------------------------------------------------------
  # WMA computation
  # ---------------------------------------------------------------------------

  # values: newest-first list; period: how many values the WMA wants.
  # Cold-start when fewer values are available: uses whatever's there with
  # adjusted weights.  Weights: newest = N, next = N-1, ..., oldest = 1.
  defp compute_wma([], _period), do: 0.0

  defp compute_wma(values, period) do
    window = Enum.take(values, period)
    n = length(window)

    # window is newest-first, so weight decreases as we move toward the tail
    {weighted_sum, weight_sum} =
      window
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0}, fn {v, i}, {ws, wt} ->
        weight = n - i
        {ws + v * weight, wt + weight}
      end)

    weighted_sum / weight_sum
  end

  # ---------------------------------------------------------------------------
  # HMA computation
  # ---------------------------------------------------------------------------

  # Called only when length(stream.values) >= period.
  defp compute_hma(stream, period) do
    buffer_size = round(:math.sqrt(period))

    {hma_state, stream} =
      case Map.get(stream.hma, period) do
        nil ->
          # Bootstrap from full available history.
          buffer = bootstrap_raw_buffer(stream.values, period, buffer_size)
          hma_state = %{raw_buffer: buffer}

          # Grow max_period to cover period (and period/2).
          stream =
            stream
            |> maybe_grow_max_period(period)
            |> put_hma(period, hma_state)

          {hma_state, stream}

        existing ->
          stream = maybe_grow_max_period(stream, period)
          {existing, stream}
      end

    # Final WMA of the raw_buffer with window = round(sqrt(period))
    hma_value = compute_wma(hma_state.raw_buffer, buffer_size)

    # Only trim after HMA accumulator is set up — trimming before bootstrap
    # would lose history the bootstrap needed.
    stream = trim_values(stream)

    {hma_value, stream}
  end

  # Replays historical values oldest-first to build up the raw_buffer
  # incrementally, keeping the last buffer_size derived values.
  defp bootstrap_raw_buffer(values_newest_first, period, buffer_size) do
    wma1_period = div(period, 2)
    wma2_period = period

    # Rebuild prefixes: for each suffix (oldest→newest), compute raw over the
    # values available *up to that point*.  values[k..end] in newest-first is
    # the "history up to value at index k" where index 0 is the newest.
    total = length(values_newest_first)

    # For each position i (0 = newest), the "history-so-far" is values[i..]
    # (newest-first), which corresponds to all values up to and including the
    # i-th-from-newest value.  Walk from oldest-position (total-1) down to 0
    # so we emit raw values in chronological order.
    raws_oldest_first =
      for i <- (total - 1)..0//-1 do
        window = Enum.drop(values_newest_first, i)
        wma1 = compute_wma(window, wma1_period)
        wma2 = compute_wma(window, wma2_period)
        2 * wma1 - wma2
      end

    # Convert to newest-first and take the last `buffer_size` raws.
    raws_oldest_first
    |> Enum.reverse()
    |> Enum.take(buffer_size)
  end

  defp put_hma(stream, period, hma_state) do
    %{stream | hma: Map.put(stream.hma, period, hma_state)}
  end

  # ---------------------------------------------------------------------------
  # Buffer management
  # ---------------------------------------------------------------------------

  defp maybe_grow_max_period(%{max_period: mp} = stream, period) when period > mp,
    do: %{stream | max_period: period}

  defp maybe_grow_max_period(stream, _period), do: stream

  defp trim_values(%{max_period: 0} = stream), do: stream

  defp trim_values(stream) do
    %{stream | values: Enum.take(stream.values, stream.max_period)}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule WeightedMovingAverageTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = WeightedMovingAverage.start_link([])
    %{wma: pid}
  end

  defp close_to(a, b, eps \\ 1.0e-9), do: abs(a - b) <= eps

  # -------------------------------------------------------
  # Empty / no-data behavior
  # -------------------------------------------------------

  test "get on empty stream returns :no_data", %{wma: s} do
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "x", :wma, 3)
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "x", :hma, 4)
  end

  # -------------------------------------------------------
  # WMA math
  # -------------------------------------------------------

  test "WMA with full window is correctly weighted", %{wma: s} do
    for v <- [10, 20, 30, 40, 50], do: WeightedMovingAverage.push(s, "a", v)

    # Newest-first: [50, 40, 30, 20, 10]
    # WMA(period=5): (5*50 + 4*40 + 3*30 + 2*20 + 1*10) / 15
    #              = (250 + 160 + 90 + 40 + 10) / 15 = 550 / 15
    expected = 550 / 15

    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 5)
    assert close_to(result, expected)
  end

  test "WMA with period smaller than buffer uses only the newest N", %{wma: s} do
    for v <- [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], do: WeightedMovingAverage.push(s, "a", v)

    # Newest-first: [10, 9, 8, ...]. WMA(3): (3*10 + 2*9 + 1*8) / 6 = 56 / 6
    expected = 56 / 6
    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert close_to(result, expected)
  end

  test "WMA cold-start (fewer values than period) uses adjusted weights", %{wma: s} do
    # TODO
  end

  test "single-value WMA equals that value", %{wma: s} do
    WeightedMovingAverage.push(s, "a", 42)
    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 10)
    assert result == 42.0
  end

  # -------------------------------------------------------
  # Memory bounds for WMA
  # -------------------------------------------------------

  test "WMA values buffer is bounded by max_period", %{wma: s} do
    for v <- 1..20, do: WeightedMovingAverage.push(s, "a", v)

    # Ask for period 3 — max_period becomes 3, buffer trims to 3.
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)

    # Push more values; buffer should stay at 3 (the current max_period).
    for v <- 21..30, do: WeightedMovingAverage.push(s, "a", v)
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)

    state = :sys.get_state(s)
    assert length(state.streams["a"].values) == 3
  end

  test "larger period grows max_period and retains more history", %{wma: s} do
    for v <- 1..5, do: WeightedMovingAverage.push(s, "a", v)

    _ = WeightedMovingAverage.get(s, "a", :wma, 3)
    state1 = :sys.get_state(s)
    assert state1.streams["a"].max_period == 3

    # Requesting a larger period grows max_period but should not truncate.
    _ = WeightedMovingAverage.get(s, "a", :wma, 10)
    state2 = :sys.get_state(s)
    assert state2.streams["a"].max_period == 10
  end

  # -------------------------------------------------------
  # HMA math
  # -------------------------------------------------------

  test "HMA with insufficient values returns :insufficient_data", %{wma: s} do
    for v <- [1, 2, 3], do: WeightedMovingAverage.push(s, "a", v)

    assert {:error, :insufficient_data} = WeightedMovingAverage.get(s, "a", :hma, 4)
  end

  test "HMA(period=4) with just-enough history computes correctly", %{wma: s} do
    values = [1, 2, 3, 4]
    for v <- values, do: WeightedMovingAverage.push(s, "a", v)

    # wma1_period = 2, wma2_period = 4, buffer_size = round(sqrt(4)) = 2
    # Replay oldest-first = [1, 2, 3, 4]:
    #   step 1 (only 1 seen, newest-first [1]):
    #     WMA cold-start uses weights n..1 over n values, where n is
    #     min(requested period, available window) — not the full requested period.
    #     For 1 value with period 2: weights [1], denominator 1 → WMA = 1.0.
    #     wma1 over period 2 using [1]: 1.0
    #     wma2 over period 4 with [1]: weights [1], denominator 1 → 1.0
    #   raw_1 = 2*1 - 1 = 1.0
    # step 2 (newest-first [2, 1]):
    #   wma1 over period 2 with [2, 1]: (2*2 + 1*1)/3 = 5/3
    #   wma2 over period 4 with [2, 1]: weights [2, 1], denominator 3 → (2*2+1*1)/3 = 5/3
    #   raw_2 = 2*(5/3) - 5/3 = 5/3
    # step 3 (newest-first [3, 2, 1]):
    #   wma1 over period 2 with [3, 2, 1] → take first 2 → [3, 2]: (2*3+1*2)/3 = 8/3
    #   wma2 over period 4 with [3, 2, 1]: weights [3,2,1] → (9+4+1)/6 = 14/6 = 7/3
    #   raw_3 = 2*(8/3) - 7/3 = 16/3 - 7/3 = 9/3 = 3.0
    # step 4 (newest-first [4, 3, 2, 1]):
    #   wma1 over period 2 with [4, 3]: (2*4+1*3)/3 = 11/3
    #   wma2 over period 4 with [4, 3, 2, 1]: (4*4+3*3+2*2+1*1)/10 = (16+9+4+1)/10 = 30/10 = 3.0
    #   raw_4 = 2*(11/3) - 3 = 22/3 - 9/3 = 13/3
    #
    # raw_buffer (newest-first, trimmed to 2): [13/3, 3.0]
    # HMA = WMA([13/3, 3.0], period 2) = (2*13/3 + 1*3.0)/3 = (26/3 + 3)/3 = (26/3 + 9/3)/3 = (35/3)/3 = 35/9

    expected = 35 / 9
    {:ok, result} = WeightedMovingAverage.get(s, "a", :hma, 4)
    assert close_to(result, expected, 1.0e-9)
  end

  test "HMA incrementally updates on new pushes", %{wma: s} do
    for v <- [1, 2, 3, 4], do: WeightedMovingAverage.push(s, "a", v)
    {:ok, h4} = WeightedMovingAverage.get(s, "a", :hma, 4)

    # Push a new value and check that HMA has been incrementally extended
    # (bootstrap path runs only once — future pushes must update the buffer).
    WeightedMovingAverage.push(s, "a", 10)
    {:ok, h5} = WeightedMovingAverage.get(s, "a", :hma, 4)

    refute close_to(h4, h5, 1.0e-12)
  end

  test "HMA bootstrap uses full retained history", %{wma: s} do
    # Push many values with no prior gets — buffer is full history.
    for v <- 1..20, do: WeightedMovingAverage.push(s, "a", v)

    # First HMA request bootstraps from all 20 values.
    {:ok, result} = WeightedMovingAverage.get(s, "a", :hma, 4)

    # Now compare to a fresh server that does the same via only WMA requests
    # (which do not register HMA accumulators).  Both must match.
    {:ok, fresh} = WeightedMovingAverage.start_link([])
    for v <- 1..20, do: WeightedMovingAverage.push(fresh, "b", v)
    {:ok, result_b} = WeightedMovingAverage.get(fresh, "b", :hma, 4)

    assert close_to(result, result_b)
  end

  # -------------------------------------------------------
  # Stream independence
  # -------------------------------------------------------

  test "different stream names are independent", %{wma: s} do
    for v <- 1..5, do: WeightedMovingAverage.push(s, "a", v)

    {:ok, a_wma} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "b", :wma, 3)

    for v <- 100..104, do: WeightedMovingAverage.push(s, "b", v)
    {:ok, b_wma} = WeightedMovingAverage.get(s, "b", :wma, 3)

    refute close_to(a_wma, b_wma)

    # "a" unaffected by pushes to "b"
    {:ok, a_wma_again} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert close_to(a_wma, a_wma_again)
  end

  # -------------------------------------------------------
  # Input validation
  # -------------------------------------------------------

  test "get with unknown type raises a FunctionClauseError", %{wma: s} do
    assert_raise FunctionClauseError, fn ->
      WeightedMovingAverage.get(s, "a", :nope, 3)
    end
  end

  test "push rejects non-numeric values", %{wma: s} do
    assert_raise FunctionClauseError, fn ->
      WeightedMovingAverage.push(s, "a", :not_a_number)
    end
  end
end
```
