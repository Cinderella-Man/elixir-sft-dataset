defmodule StreamingPercentile do
  @moduledoc """
  A `GenServer` that maintains multiple named numeric streams and answers
  percentile (quantile) queries over a count-based sliding window.

  Each stream keeps at most `max_window_size` of the most recently pushed values,
  where `max_window_size` is the **largest** `window_size` ever supplied for that
  stream (the bound grows over time and never shrinks).

  Quantiles are computed with the linear-interpolation method — the same one used
  by NumPy's default `method: "linear"` and Excel's `PERCENTILE.INC`:

      rank = q * (N - 1)
      lo   = floor(rank)
      hi   = ceil(rank)
      result =
        if lo == hi,
          do: sorted[lo],
          else: sorted[lo] + (rank - lo) * (sorted[hi] - sorted[lo])

  Therefore `q = 0.0` yields the minimum and `q = 1.0` the maximum.

  The window is stored as a plain list in insertion order (newest first) and is
  snapshot-sorted at query time, so a query costs `O(N log N)`. The batch form
  `percentiles/3` sorts once and evaluates every requested quantile against that
  single sorted snapshot.

  Streams are completely independent of one another.

  ## Example

      {:ok, pid} = StreamingPercentile.start_link([])
      Enum.each(1..100, &StreamingPercentile.push(pid, :latency, &1, 100))

      StreamingPercentile.percentile(pid, :latency, 0.5)
      #=> {:ok, 50.5}

      StreamingPercentile.percentiles(pid, :latency, [0.5, 0.95, 0.99])
      #=> {:ok, %{0.5 => 50.5, 0.95 => 95.05, 0.99 => 99.01}}
  """

  use GenServer

  @typedoc "The name identifying a stream. Any term may be used."
  @type stream_name :: term()

  @typedoc "A quantile expressed as a float in the closed interval `[0.0, 1.0]`."
  @type quantile :: float()

  @typedoc "A started server: a pid or a registered name."
  @type server :: GenServer.server()

  @typedoc "Per-stream state: the newest-first window and the largest window size seen."
  @type stream :: %{values: [number()], max_window_size: pos_integer()}

  @typedoc "The GenServer state: a map of stream name to stream data."
  @type state :: %{optional(stream_name()) => stream()}

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the percentile server.

  Accepts the usual `GenServer` options; in particular `:name` may be given to
  register the process.

      {:ok, _pid} = StreamingPercentile.start_link(name: :metrics)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name] ++ rest, else: rest
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Appends `value` to the sliding window of the stream `name`.

  `window_size` is the maximum number of values retained for the stream. When a
  larger `window_size` is supplied later for the same stream, the retention bound
  grows; it never shrinks.

  Raises `FunctionClauseError` if `value` is not a number or if `window_size` is
  not a positive integer.

  Always returns `:ok`.
  """
  @spec push(server(), stream_name(), number(), pos_integer()) :: :ok
  def push(server, name, value, window_size)
      when is_number(value) and is_integer(window_size) and window_size > 0 do
    GenServer.cast(server, {:push, name, value, window_size})
  end

  @doc """
  Returns the quantile `q` of the stream `name`'s current window.

  `q` must be a float in `[0.0, 1.0]`; `0.0` yields the minimum and `1.0` the
  maximum. Returns `{:ok, float}`, `{:error, :no_data}` when the stream holds no
  values, or `{:error, :invalid_quantile}` when `q` is out of range.
  """
  @spec percentile(server(), stream_name(), quantile()) ::
          {:ok, float()} | {:error, :no_data | :invalid_quantile}
  def percentile(server, name, q) do
    if valid_quantile?(q) do
      GenServer.call(server, {:percentile, name, q})
    else
      {:error, :invalid_quantile}
    end
  end

  @doc """
  Computes several quantiles of the stream `name` in a single call.

  `q_list` must be a non-empty list of floats in `[0.0, 1.0]`. The window is
  sorted exactly once and every quantile is evaluated against that snapshot.

  Returns `{:ok, map}` mapping each requested `q` to its value, `{:error,
  :no_data}` when the stream holds no values, or `{:error, :invalid_quantile}` if
  *any* element of `q_list` is out of range (no partial results are returned).
  """
  @spec percentiles(server(), stream_name(), [quantile(), ...]) ::
          {:ok, %{quantile() => float()}} | {:error, :no_data | :invalid_quantile}
  def percentiles(server, name, q_list) when is_list(q_list) and q_list != [] do
    if Enum.all?(q_list, &valid_quantile?/1) do
      GenServer.call(server, {:percentiles, name, q_list})
    else
      {:error, :invalid_quantile}
    end
  end

  @doc """
  Returns the current window contents of the stream `name` as floats, in insertion
  order (oldest first, newest last).

  Returns `{:error, :no_data}` when the stream holds no values.
  """
  @spec window(server(), stream_name()) :: {:ok, [float()]} | {:error, :no_data}
  def window(server, name) do
    GenServer.call(server, {:window, name})
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl GenServer
  @spec init(:ok) :: {:ok, state()}
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_cast({:push, name, value, window_size}, state) do
    stream =
      case Map.fetch(state, name) do
        {:ok, %{values: values, max_window_size: max_size}} ->
          new_max = max(max_size, window_size)
          %{values: trim([value | values], new_max), max_window_size: new_max}

        :error ->
          %{values: [value], max_window_size: window_size}
      end

    {:noreply, Map.put(state, name, stream)}
  end

  @impl GenServer
  def handle_call({:percentile, name, q}, _from, state) do
    reply =
      case sorted_window(state, name) do
        {:ok, sorted} -> {:ok, quantile_of(sorted, length(sorted), q)}
        :error -> {:error, :no_data}
      end

    {:reply, reply, state}
  end

  def handle_call({:percentiles, name, q_list}, _from, state) do
    reply =
      case sorted_window(state, name) do
        {:ok, sorted} ->
          n = length(sorted)
          {:ok, Map.new(q_list, fn q -> {q, quantile_of(sorted, n, q)} end)}

        :error ->
          {:error, :no_data}
      end

    {:reply, reply, state}
  end

  def handle_call({:window, name}, _from, state) do
    reply =
      case Map.fetch(state, name) do
        {:ok, %{values: [_ | _] = values}} ->
          {:ok, values |> Enum.reverse() |> Enum.map(&(&1 * 1.0))}

        _other ->
          {:error, :no_data}
      end

    {:reply, reply, state}
  end

  # --------------------------------------------------------------------------
  # Internal helpers
  # --------------------------------------------------------------------------

  @spec valid_quantile?(term()) :: boolean()
  defp valid_quantile?(q) when is_float(q), do: q >= +0.0 and q <= 1.0
  defp valid_quantile?(_q), do: false

  # Keeps at most `max_size` newest-first entries.
  @spec trim([number()], pos_integer()) :: [number()]
  defp trim(values, max_size), do: Enum.take(values, max_size)

  @spec sorted_window(state(), stream_name()) :: {:ok, [number(), ...]} | :error
  defp sorted_window(state, name) do
    case Map.fetch(state, name) do
      {:ok, %{values: [_ | _] = values}} -> {:ok, Enum.sort(values)}
      _other -> :error
    end
  end

  # Linear interpolation between the two nearest ranks of an ascending list.
  @spec quantile_of([number(), ...], pos_integer(), quantile()) :: float()
  defp quantile_of([single], 1, _q), do: single * 1.0

  defp quantile_of(sorted, n, q) do
    rank = q * (n - 1)
    lo = rank |> Float.floor() |> trunc()
    hi = rank |> Float.ceil() |> trunc()

    if lo == hi do
      sorted |> Enum.at(lo) |> Kernel.*(1.0)
    else
      lo_value = Enum.at(sorted, lo) * 1.0
      hi_value = Enum.at(sorted, hi) * 1.0
      lo_value + (rank - lo) * (hi_value - lo_value)
    end
  end
end