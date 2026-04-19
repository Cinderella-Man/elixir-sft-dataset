Implement the `handle_info/2` callback for the `:cleanup` message.

First, retrieve the current time using `state.clock.()`. Then, filter the `state.counters` map to remove expired entries. The values in the counters map are tuples structured as `{count, window_end}`. You should retain only the entries where `window_end` is strictly greater than the current time, dropping any windows that have fully passed.

Next, ensure the periodic cleanup continues by executing `schedule_cleanup/1` with `state.cleanup_interval_ms`.

Finally, return `{:noreply, updated_state}` with the newly filtered counters map.

```elixir
defmodule FixedWindowLimiter do
  @moduledoc """
  A GenServer that enforces per-key rate limits using a fixed-window counter.

  Time is snapped into discrete windows of size `window_ms`: a timestamp `t`
  belongs to window `div(t, window_ms)`.  Each `{key, window_index}` pair has
  its own counter.  A request is allowed if the counter for the current
  window is below `max_requests`, in which case the counter is incremented.

  Because windows are absolute, counters reset abruptly at window boundaries.
  This allows up to `2 * max_requests` requests across a boundary (e.g.,
  `max_requests` at the very end of window N and another `max_requests` at
  the very start of window N+1).  That is a known property of the fixed-
  window counter algorithm and is accepted here as a tradeoff for
  implementation simplicity and O(1) state per key.

  Expired counters are pruned during a periodic sweep so the process doesn't
  leak memory for keys that stop receiving traffic.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = FixedWindowLimiter.start_link([])
      iex> {:ok, 4} = FixedWindowLimiter.check(pid, "user:1", 5, 1_000)
      iex> {:ok, 3} = FixedWindowLimiter.check(pid, "user:1", 5, 1_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the FixedWindowLimiter process and links it to the caller.

  ## Options

    * `:name`                 – optional registered name
    * `:clock`                – `(-> integer())` returning now in milliseconds
    * `:cleanup_interval_ms`  – sweep interval (default `60_000`)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Checks whether a request for `key` is allowed in the current fixed window.

  Returns `{:ok, remaining}` when the request is accepted, where `remaining`
  is the number of additional requests permitted in the same window.

  Returns `{:error, :rate_limited, retry_after_ms}` when the window's counter
  has reached `max_requests`.  `retry_after_ms` is the wait (in milliseconds)
  until the current window ends and a fresh counter begins.
  """
  @spec check(GenServer.server(), term(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests > 0 and
           is_integer(window_ms) and window_ms > 0 do
    GenServer.call(server, {:check, key, max_requests, window_ms})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{{key, window_index} => {count, window_end_time}}
       counters: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()

    # Snap `now` into the absolute window it belongs to.
    window_index = div(now, window_ms)
    window_end = (window_index + 1) * window_ms
    counter_key = {key, window_index}

    count = Map.get(state.counters, counter_key, {0, window_end}) |> elem(0)

    if count < max_requests do
      new_count = count + 1
      remaining = max_requests - new_count
      new_counters = Map.put(state.counters, counter_key, {new_count, window_end})

      {:reply, {:ok, remaining}, %{state | counters: new_counters}}
    else
      # Counter saturated; wait until this window ends.
      retry_after = max(window_end - now, 1)
      {:reply, {:error, :rate_limited, retry_after}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    # TODO
  end

  # Catch-all so unexpected messages don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```