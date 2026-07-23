# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule MovingAverage do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams and computes
  Simple Moving Averages (SMA) and Exponential Moving Averages (EMA) on demand.

  ## State layout

      %{
        streams: %{
          stream_name => %{
            values:      [float]  # newest-first list; trimmed at get/4 time, never at push/3 time
            max_period:  integer  # largest period ever seen via get/4
            total_count: integer  # total number of values pushed (monotonically increasing)
            ema:         %{period => float}  # running EMA accumulator per period
          }
        }
      }

  ## Memory contract

    * **SMA** — `values` is a plain list trimmed to `max_period` entries **at get time**,
      but only when the requested period does not cause `max_period` to grow.  When a
      larger period is first seen, the buffer is left untouched so that the wider
      window has access to all values accumulated since the last trim.  After any
      same-or-smaller-period `get/4` call the buffer length is ≤ `max_period`.
    * **EMA** — one `float` accumulator per `(name, period)` pair.  `push/3` updates
      every registered accumulator in O(distinct EMA periods).  A new EMA period
      bootstraps from the full current `values` buffer *before* any trimming occurs,
      then is maintained incrementally on future pushes.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `MovingAverage` server.

  ## Options

    * `:name` – optional registration name passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Appends `value` to the named stream.  Creates the stream on first use.
  Always returns `:ok`.
  """
  @spec push(GenServer.server(), term(), number()) :: :ok
  def push(server, name, value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Computes an average over the named stream.

    * `type`   – `:sma` or `:ema`
    * `period` – positive integer window size

  Returns `{:ok, float}` or `{:error, :no_data}` if nothing has been pushed yet.
  """
  @spec get(GenServer.server(), term(), :sma | :ema, pos_integer()) ::
          {:ok, float()} | {:error, :no_data}
  def get(server, name, type, period)
      when type in [:sma, :ema] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, %{streams: %{}}}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream =
      state
      |> stream_for(name)
      |> push_value(value)

    {:reply, :ok, put_stream(state, name, stream)}
  end

  def handle_call({:get, name, type, period}, _from, state) do
    stream = stream_for(state, name)

    if stream.total_count == 0 do
      {:reply, {:error, :no_data}, state}
    else
      {result, stream} = compute(stream, type, period)
      {:reply, {:ok, result}, put_stream(state, name, stream)}
    end
  end

  # ---------------------------------------------------------------------------
  # Stream helpers
  # ---------------------------------------------------------------------------

  defp stream_for(state, name) do
    Map.get(state.streams, name, new_stream())
  end

  defp put_stream(state, name, stream) do
    %{state | streams: Map.put(state.streams, name, stream)}
  end

  defp new_stream do
    %{
      # newest-first plain list; never trimmed during push
      values: [],
      max_period: 0,
      total_count: 0,
      ema: %{}
    }
  end

  # ---------------------------------------------------------------------------
  # push_value/2
  #
  # Prepends the value and updates every registered EMA accumulator.
  # Deliberately does NOT trim `values` — trimming is deferred to compute/3
  # so that a later get/4 with a larger period can still see all recent values.
  # ---------------------------------------------------------------------------

  defp push_value(stream, value) when is_number(value) do
    value = value * 1.0

    updated_emas =
      Map.new(stream.ema, fn {period, prev_ema} ->
        {period, ema_step(prev_ema, value, period)}
      end)

    %{
      stream
      | values: [value | stream.values],
        total_count: stream.total_count + 1,
        ema: updated_emas
    }
  end

  # ---------------------------------------------------------------------------
  # compute/3
  #
  # Trimming policy (applied after the result is computed):
  #   • If `period` > current `max_period`  →  max_period GROWS; do NOT trim.
  #     The buffer keeps all values so a subsequent get with this larger period
  #     can still see them on future calls.
  #   • If `period` ≤ current `max_period`  →  max_period stays; TRIM to max_period.
  #     This is the steady-state path that enforces the memory bound.
  #
  # For EMA the bootstrap always reads the pre-trim buffer so it uses the
  # maximum available history.
  # ---------------------------------------------------------------------------

  defp compute(stream, :sma, period) do
    {grew, stream} = maybe_grow_max_period(stream, period)
    stream = if grew, do: stream, else: trim_values(stream)

    window = Enum.take(stream.values, period)
    sma = Enum.sum(window) / length(window)
    {sma, stream}
  end

  defp compute(stream, :ema, period) do
    case Map.get(stream.ema, period) do
      nil ->
        # Bootstrap from the full buffer BEFORE any trim (oldest-first).
        ema_val =
          stream.values
          |> Enum.reverse()
          |> bootstrap_ema(period)

        {grew, stream} = maybe_grow_max_period(stream, period)
        stream = if grew, do: stream, else: trim_values(stream)
        stream = %{stream | ema: Map.put(stream.ema, period, ema_val)}
        {ema_val, stream}

      ema_val ->
        # Accumulator already current from incremental push_value updates.
        {grew, stream} = maybe_grow_max_period(stream, period)
        stream = if grew, do: stream, else: trim_values(stream)
        {ema_val, stream}
    end
  end

  # ---------------------------------------------------------------------------
  # EMA arithmetic
  # ---------------------------------------------------------------------------

  # Expects values in oldest-first order.
  defp bootstrap_ema([], _period), do: 0.0

  defp bootstrap_ema([seed | rest], period) do
    Enum.reduce(rest, seed * 1.0, fn value, prev ->
      ema_step(prev, value, period)
    end)
  end

  @compile {:inline, [ema_step: 3]}
  defp ema_step(prev_ema, value, period) do
    k = 2.0 / (period + 1)
    value * k + prev_ema * (1.0 - k)
  end

  # ---------------------------------------------------------------------------
  # Buffer management — called only from compute/3, never from push_value/2
  # ---------------------------------------------------------------------------

  # Returns `{grew?, updated_stream}`.
  defp maybe_grow_max_period(%{max_period: mp} = stream, period) when period > mp,
    do: {true, %{stream | max_period: period}}

  defp maybe_grow_max_period(stream, _period),
    do: {false, stream}

  defp trim_values(%{max_period: 0} = stream), do: stream

  defp trim_values(stream) do
    %{stream | values: Enum.take(stream.values, stream.max_period)}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule MovingAverageTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = MovingAverage.start_link([])
    %{ma: pid}
  end

  # -------------------------------------------------------
  # Helper — float comparison with tolerance
  # -------------------------------------------------------

  defp assert_close(left, right, epsilon \\ 1.0e-9) do
    assert abs(left - right) < epsilon,
           "Expected #{left} to be within #{epsilon} of #{right}"
  end

  # -------------------------------------------------------
  # No-data edge case
  # -------------------------------------------------------

  test "returns error when no data has been pushed", %{ma: ma} do
    assert {:error, :no_data} = MovingAverage.get(ma, "empty", :sma, 5)
    assert {:error, :no_data} = MovingAverage.get(ma, "empty", :ema, 5)
  end

  # -------------------------------------------------------
  # SMA basics
  # -------------------------------------------------------

  test "SMA with a single value", %{ma: ma} do
    MovingAverage.push(ma, "s", 10.0)
    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    assert_close(result, 10.0)
  end

  test "SMA cold-start: fewer values than the period", %{ma: ma} do
    # Push 3 values, request SMA over period 5
    MovingAverage.push(ma, "s", 2.0)
    MovingAverage.push(ma, "s", 4.0)
    MovingAverage.push(ma, "s", 6.0)

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    # Mean of [2, 4, 6] = 4.0
    assert_close(result, 4.0)
  end

  test "SMA over exact period count", %{ma: ma} do
    Enum.each([10.0, 20.0, 30.0, 40.0, 50.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    # Mean of [10, 20, 30, 40, 50] = 30.0
    assert_close(result, 30.0)
  end

  test "SMA slides window: old values drop off", %{ma: ma} do
    Enum.each([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 3)
    # Last 3 values: [5, 6, 7], mean = 6.0
    assert_close(result, 6.0)
  end

  test "SMA with different periods on the same stream", %{ma: ma} do
    Enum.each([2.0, 4.0, 6.0, 8.0, 10.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, sma2} = MovingAverage.get(ma, "s", :sma, 2)
    # Last 2: [8, 10] -> 9.0
    assert_close(sma2, 9.0)

    assert {:ok, sma5} = MovingAverage.get(ma, "s", :sma, 5)
    # All 5: [2, 4, 6, 8, 10] -> 6.0
    assert_close(sma5, 6.0)
  end

  # -------------------------------------------------------
  # EMA basics
  # -------------------------------------------------------

  test "EMA with a single value equals that value", %{ma: ma} do
    MovingAverage.push(ma, "e", 42.0)
    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 5)
    assert_close(result, 42.0)
  end

  test "EMA hand-calculated over a known sequence", %{ma: ma} do
    # TODO
  end

  test "EMA with period 1 always equals the latest value", %{ma: ma} do
    # k = 2/(1+1) = 1.0, so ema = value * 1 + prev * 0 = value
    Enum.each([5.0, 15.0, 25.0, 100.0], &MovingAverage.push(ma, "e", &1))

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 1)
    assert_close(result, 100.0)
  end

  test "EMA cold-start: fewer values than the period still computes", %{ma: ma} do
    # Sequence: [4, 8], period 10, k = 2/11 ≈ 0.18182
    # Step 0: ema = 4
    # Step 1: ema = 8 * (2/11) + 4 * (9/11) = 16/11 + 36/11 = 52/11 ≈ 4.7273
    MovingAverage.push(ma, "e", 4.0)
    MovingAverage.push(ma, "e", 8.0)

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 10)
    assert_close(result, 52.0 / 11.0)
  end

  test "EMA with longer known sequence", %{ma: ma} do
    # Sequence: [1, 2, 3, 4, 5], period 5, k = 2/6 = 1/3
    # Step 0: ema = 1
    # Step 1: ema = 2*(1/3) + 1*(2/3) = 4/3
    # Step 2: ema = 3*(1/3) + (4/3)*(2/3) = 1 + 8/9 = 17/9
    # Step 3: ema = 4*(1/3) + (17/9)*(2/3) = 4/3 + 34/27 = 36/27 + 34/27 = 70/27
    # Step 4: ema = 5*(1/3) + (70/27)*(2/3) = 5/3 + 140/81 = 135/81 + 140/81 = 275/81
    Enum.each([1.0, 2.0, 3.0, 4.0, 5.0], &MovingAverage.push(ma, "e", &1))

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 5)
    assert_close(result, 275.0 / 81.0)
  end

  # -------------------------------------------------------
  # Stream name independence
  # -------------------------------------------------------

  test "different stream names are completely independent", %{ma: ma} do
    Enum.each([100.0, 200.0, 300.0], &MovingAverage.push(ma, "a", &1))
    MovingAverage.push(ma, "b", 999.0)

    assert {:ok, sma_a} = MovingAverage.get(ma, "a", :sma, 3)
    assert_close(sma_a, 200.0)

    assert {:ok, sma_b} = MovingAverage.get(ma, "b", :sma, 3)
    assert_close(sma_b, 999.0)

    assert {:error, :no_data} = MovingAverage.get(ma, "c", :sma, 3)
  end

  # -------------------------------------------------------
  # Memory: SMA does not store unbounded history
  # -------------------------------------------------------

  test "SMA only retains up to max_period values, not the full stream", %{ma: ma} do
    # First, request SMA with period 5 to establish max_period
    MovingAverage.push(ma, "mem", 0.0)
    MovingAverage.get(ma, "mem", :sma, 5)

    # Push 1000 more values
    for i <- 1..1000, do: MovingAverage.push(ma, "mem", i * 1.0)

    # SMA should still be correct (last 5: [996, 997, 998, 999, 1000])
    assert {:ok, result} = MovingAverage.get(ma, "mem", :sma, 5)
    assert_close(result, 998.0)

    # Because storage is bounded by max_period, the older values are gone for
    # good: a much wider window can only average the handful of retained
    # values. An unbounded buffer would answer 900.5 here (the true mean of
    # 801..1000), while a buffer holding at most ~10 recent values cannot
    # produce anything below 995.5 (the mean of 991..1000).
    assert {:ok, wide} = MovingAverage.get(ma, "mem", :sma, 200)

    assert wide > 995.0,
           "Expected a bounded buffer, but SMA over period 200 answered #{wide}, " <>
             "which implies far more than max_period values are still stored"
  end

  test "requesting a larger period grows the buffer to accommodate it", %{ma: ma} do
    # Start with period 3
    Enum.each(1..20 |> Enum.map(&(&1 * 1.0)), &MovingAverage.push(ma, "grow", &1))
    assert {:ok, sma3} = MovingAverage.get(ma, "grow", :sma, 3)
    # mean of [18, 19, 20]
    assert_close(sma3, 19.0)

    # Now request period 10 — the buffer should still work,
    # though values before the previous max_period may be lost.
    # Push 10 more values so we have enough for period 10.
    Enum.each(21..30 |> Enum.map(&(&1 * 1.0)), &MovingAverage.push(ma, "grow", &1))
    assert {:ok, sma10} = MovingAverage.get(ma, "grow", :sma, 10)
    # Last 10: [21..30], mean = 25.5
    assert_close(sma10, 25.5)
  end

  # -------------------------------------------------------
  # Memory: EMA uses only a running accumulator
  # -------------------------------------------------------

  test "EMA after a large stream matches iterative calculation", %{ma: ma} do
    n = 5_000
    period = 20
    k = 2.0 / (period + 1)

    # Compute expected EMA by hand
    values = for i <- 1..n, do: :math.sin(i / 100.0)

    expected_ema =
      values
      |> Enum.reduce(nil, fn v, acc ->
        case acc do
          nil -> v
          prev -> v * k + prev * (1 - k)
        end
      end)

    # Push same sequence into the GenServer
    Enum.each(values, &MovingAverage.push(ma, "big", &1))

    assert {:ok, result} = MovingAverage.get(ma, "big", :ema, period)
    assert_close(result, expected_ema, 1.0e-6)
  end

  # -------------------------------------------------------
  # Multiple EMA periods on the same stream
  # -------------------------------------------------------

  test "different EMA periods on the same stream produce different results", %{ma: ma} do
    Enum.each(
      [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0],
      &MovingAverage.push(ma, "multi", &1)
    )

    assert {:ok, ema3} = MovingAverage.get(ma, "multi", :ema, 3)
    assert {:ok, ema10} = MovingAverage.get(ma, "multi", :ema, 10)

    # EMA with smaller period reacts faster — should be closer to 10
    assert ema3 > ema10
  end

  # -------------------------------------------------------
  # Interleaved push and get
  # -------------------------------------------------------

  test "interleaved pushes and gets produce correct results", %{ma: ma} do
    MovingAverage.push(ma, "s", 10.0)
    assert {:ok, r1} = MovingAverage.get(ma, "s", :sma, 3)
    assert_close(r1, 10.0)

    MovingAverage.push(ma, "s", 20.0)
    assert {:ok, r2} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [10, 20]
    assert_close(r2, 15.0)

    MovingAverage.push(ma, "s", 30.0)
    assert {:ok, r3} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [10, 20, 30]
    assert_close(r3, 20.0)

    MovingAverage.push(ma, "s", 40.0)
    assert {:ok, r4} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [20, 30, 40] — 10 dropped
    assert_close(r4, 30.0)

    MovingAverage.push(ma, "s", 50.0)
    assert {:ok, r5} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [30, 40, 50]
    assert_close(r5, 40.0)
  end

  # -------------------------------------------------------
  # Constant values
  # -------------------------------------------------------

  test "constant values yield that constant for both SMA and EMA", %{ma: ma} do
    for _ <- 1..20, do: MovingAverage.push(ma, "flat", 7.0)

    assert {:ok, sma} = MovingAverage.get(ma, "flat", :sma, 5)
    assert_close(sma, 7.0)

    assert {:ok, ema} = MovingAverage.get(ma, "flat", :ema, 5)
    assert_close(ema, 7.0)
  end

  # -------------------------------------------------------
  # Process registration via the :name option
  # -------------------------------------------------------

  test "start_link registers the process under the :name option" do
    registered =
      String.to_atom("moving_average_#{System.pid()}_#{System.unique_integer([:positive])}")

    assert {:ok, pid} = MovingAverage.start_link(name: registered)
    assert Process.whereis(registered) == pid
  end

  test "a server started with :name serves push and get addressed by that name" do
    registered =
      String.to_atom("moving_average_#{System.pid()}_#{System.unique_integer([:positive])}")

    assert {:ok, _pid} = MovingAverage.start_link(name: registered)

    assert {:error, :no_data} = MovingAverage.get(registered, "named", :sma, 3)

    assert :ok = MovingAverage.push(registered, "named", 4.0)
    assert :ok = MovingAverage.push(registered, "named", 8.0)

    assert {:ok, sma} = MovingAverage.get(registered, "named", :sma, 2)
    # mean of [4, 8]
    assert_close(sma, 6.0)

    # k = 2/(2+1) = 2/3; seed 4, then 8*(2/3) + 4*(1/3) = 20/3
    assert {:ok, ema} = MovingAverage.get(registered, "named", :ema, 2)
    assert_close(ema, 20.0 / 3.0)
  end
end
```
