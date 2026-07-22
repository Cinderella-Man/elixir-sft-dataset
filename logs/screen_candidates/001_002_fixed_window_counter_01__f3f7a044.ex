defmodule FixedWindowLimiter do
  @moduledoc """
  A `GenServer` that enforces per-key rate limits using a fixed-window counter
  algorithm.

  Time is snapped into discrete, absolute windows: the window a timestamp
  belongs to is `div(timestamp, window_ms)`. Every `{key, window_index}` pair
  keeps its own independent counter. Within a window the first `max_requests`
  calls for a key are allowed; once the counter reaches `max_requests` further
  calls are rejected until the next window begins.

  Because windows are absolute rather than relative, counters reset abruptly at
  window boundaries. This means a client can send `max_requests` at the very end
  of one window and `max_requests` again at the start of the next, briefly
  doubling the effective rate. That is a well-known property of fixed-window
  counters and is accepted here by design.

  Expired counters (those whose window has fully ended) are removed by a periodic
  cleanup pass so the process does not accumulate stale state indefinitely.
  """

  use GenServer

  @default_cleanup_interval_ms 60_000

  @typedoc "A rate-limit key. Any term uniquely identifying a caller/resource."
  @type key :: term()

  @typedoc "Internal server state."
  @type state :: %{
          clock: (-> integer()),
          cleanup_interval_ms: non_neg_integer() | :infinity,
          counters: %{optional({key(), integer()}) => {non_neg_integer(), integer()}}
        }

  # Public API

  @doc """
  Starts the rate limiter process.

  ## Options

    * `:clock` - a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` - an optional name for process registration.
    * `:cleanup_interval_ms` - how often, in milliseconds, to run the cleanup
      pass. Defaults to `#{@default_cleanup_interval_ms}`. May be `:infinity`,
      in which case no periodic cleanup timer is ever scheduled.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Checks whether a request for `key` is allowed under the given limit.

  `max_requests` is the maximum number of requests permitted per window and
  `window_ms` is the window size in milliseconds.

  Returns `{:ok, remaining}` when the request is allowed, where `remaining` is
  the number of further requests permitted in the current window after this one.

  Returns `{:error, :rate_limited, retry_after_ms}` when the limit has been
  reached, where `retry_after_ms` is the number of milliseconds until the
  current window ends and the counter resets.
  """
  @spec check(GenServer.server(), key(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests > 0 and
             is_integer(window_ms) and window_ms > 0 do
    GenServer.call(server, {:check, key, max_requests, window_ms})
  end

  # GenServer callbacks

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{clock: clock, cleanup_interval_ms: interval, counters: %{}}
    schedule_cleanup(interval)
    {:ok, state}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()
    window_index = div(now, window_ms)
    window_end = (window_index + 1) * window_ms
    entry_key = {key, window_index}

    {count, _end} = Map.get(state.counters, entry_key, {0, window_end})

    if count < max_requests do
      counters = Map.put(state.counters, entry_key, {count + 1, window_end})
      remaining = max_requests - (count + 1)
      {:reply, {:ok, remaining}, %{state | counters: counters}}
    else
      retry_after_ms = window_end - now
      {:reply, {:error, :rate_limited, retry_after_ms}, state}
    end
  end

  @impl true
  def handle_info(:__periodic_cleanup__, state) do
    new_state = purge_expired(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, new_state}
  end

  def handle_info(:cleanup, state) do
    {:noreply, purge_expired(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Internal helpers

  @spec schedule_cleanup(non_neg_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) and interval >= 0 do
    Process.send_after(self(), :__periodic_cleanup__, interval)
    :ok
  end

  @spec purge_expired(state()) :: state()
  defp purge_expired(state) do
    now = state.clock.()

    counters =
      Map.filter(state.counters, fn {_entry_key, {_count, window_end}} ->
        window_end >= now
      end)

    %{state | counters: counters}
  end
end