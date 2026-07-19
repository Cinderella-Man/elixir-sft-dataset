# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `trim_values` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `WeightedMovingAverage` that maintains multiple named streams of numeric values and computes **Weighted Moving Average (WMA)** and **Hull Moving Average (HMA)** on demand.

Unlike SMA (which treats every value in the window equally) or EMA (which geometrically decays older values), WMA assigns **linear weights**: the newest value gets weight `N`, the second newest gets weight `N-1`, down to the oldest in-window value with weight `1`. HMA is a composite — it's the WMA of `2*WMA(period/2) - WMA(period)` with a final WMA of `sqrt(period)`. HMA is used in technical analysis for its reduced lag relative to WMA while preserving smoothness.

I need these functions in the public API:

- `WeightedMovingAverage.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `WeightedMovingAverage.push(server, name, value)` which appends a numeric value to the named stream. Returns `:ok`. The `value` must be a number — guard the function with `is_number/1` so that a non-numeric `value` (e.g. an atom) raises `FunctionClauseError`.

- `WeightedMovingAverage.get(server, name, type, period)` which computes an average over the named stream. `type` is either `:wma` or `:hma`, and `period` is a positive integer. Guard the function so that any `type` other than `:wma` or `:hma` raises `FunctionClauseError`. Returns `{:ok, float}` or `{:error, :no_data}` if no values have been pushed, or `{:error, :insufficient_data}` if the stream has fewer values than needed to produce a meaningful HMA (specifically, when `:hma` is requested and the stream has fewer than `period` values; `:wma` with fewer values falls back to cold-start over whatever is available).

**WMA math.** For a window of N values `[v_newest, v2, ..., v_oldest]`, WMA = `(N*v_newest + (N-1)*v2 + ... + 1*v_oldest) / (N + (N-1) + ... + 1)`. The denominator is `N*(N+1)/2`. Cold-start (fewer than `period` values available): compute the WMA over all available values, with weights adjusted — e.g. with 3 of 5 values available, weights are `[3, 2, 1]` and denominator is `6`.

**HMA math.** For `period = P`:
1. Compute `wma1 = WMA(period = P/2)` using integer division.
2. Compute `wma2 = WMA(period = P)`.
3. Compute `raw = 2 * wma1 - wma2`.
4. Maintain a rolling buffer of `raw` values (one per push that happens after the HMA accumulator has been established for this stream/period). The HMA is then `WMA(raw_buffer, period = round(sqrt(P)))`.

HMA must be computed **incrementally** — every push must produce a new `raw` value and append it to the HMA's rolling buffer. When `:hma` is requested with a new `period` for the first time, the buffer must be bootstrapped from the full available history: replay every stored value to build up the `raw` series retroactively, and store the bootstrapped state for future incremental updates.

**Memory constraints.**

- For WMA, keep the last `max_period` values per stream, where `max_period` is the largest period ever requested for that stream (via `:wma` directly OR indirectly via an `:hma` query). Store values newest-first as a plain list.

- For HMA, store per `(name, period)` pair:
  - `raw_buffer` — a list of derived `raw` values, newest-first, bounded by `round(sqrt(period))` entries
  - `wma1_period = div(period, 2)` and `wma2_period = period` are recomputable from `period`, so don't store them

When a push happens and a stream has one or more registered HMA periods, each push must recompute `wma1`, `wma2`, `raw`, and append `raw` to each HMA's `raw_buffer`. This means push is O(distinct HMA periods × max_wma_period) in the worst case — acceptable for finite registered periods.

Different stream names must be completely independent.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `trim_values` missing

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

  defp trim_values(%{max_period: 0} = stream) do
    # TODO
  end
end
```

Give me only the complete implementation of `trim_values` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
