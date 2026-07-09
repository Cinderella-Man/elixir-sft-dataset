Implement the GenServer callback `handle_call/3`. It has four clauses, one per
request tag, each returning a `{:reply, reply, state}` tuple. All of them begin by
resolving the target stream with `stream_for(state, name)`.

- **`{:push, name, value, window_size}`** — appends a value to the named stream's
  sliding window. Grow the retention bound to `max(stream.max_window_size,
  window_size)` (it never shrinks). Coerce `value` to a float, prepend it to the
  stream's `values` (newest-first), and trim the list to at most the new maximum
  size with `Enum.take/2`. Store the updated `%{values: …, max_window_size: …}`
  stream back into the state via `put_stream/3` and reply with `:ok`.

- **`{:percentile, name, q}`** — if the stream's `values` list is empty, reply
  `{:error, :no_data}`. Otherwise sort the window ascending with `Enum.sort/1` and
  reply `{:ok, quantile(sorted, q)}`. The state is unchanged.

- **`{:percentiles, name, q_list}`** — if the stream is empty, reply
  `{:error, :no_data}`. Otherwise sort the window once, compute `quantile(sorted, q)`
  for every `q` in `q_list`, and reply `{:ok, map}` where the map associates each `q`
  with its result (use `Map.new/2`). The state is unchanged.

- **`{:window, name}`** — if the stream is empty, reply `{:error, :no_data}`.
  Otherwise reply `{:ok, list}` with the window contents in insertion order
  (oldest → newest) by reversing the newest-first `values`. The state is unchanged.

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

  def handle_call({:push, name, value, window_size}, _from, state) do
    # TODO
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