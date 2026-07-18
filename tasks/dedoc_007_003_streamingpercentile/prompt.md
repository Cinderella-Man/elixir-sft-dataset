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
defmodule StreamingPercentile do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def push(server, name, value, window_size)
      when is_number(value) and is_integer(window_size) and window_size > 0 do
    GenServer.call(server, {:push, name, value, window_size})
  end

  def percentile(server, name, q) when is_float(q) or is_integer(q) do
    if valid_quantile?(q) do
      GenServer.call(server, {:percentile, name, q * 1.0})
    else
      {:error, :invalid_quantile}
    end
  end

  def percentiles(server, name, [_ | _] = q_list) do
    if Enum.all?(q_list, &valid_quantile?/1) do
      GenServer.call(server, {:percentiles, name, Enum.map(q_list, &(&1 * 1.0))})
    else
      {:error, :invalid_quantile}
    end
  end

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
