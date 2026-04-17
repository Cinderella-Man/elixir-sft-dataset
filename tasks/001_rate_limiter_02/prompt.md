You are given a partial implementation of an Elixir `RateLimiter` using a GenServer. The public API and state initialization are already implemented. Your task is to implement the `handle_call/3` callback that processes the `{:check, key, max_requests, window_ms}` message.

**Requirements:**
1.  **Pruning:** Remove any timestamps for the given key that are older than the current sliding window.
2.  **Logic:** If the number of active timestamps is less than `max_requests`, add the current timestamp and return `{:ok, remaining}`.
3.  **Rate Limiting:** If the limit is reached, do not add a new timestamp. Instead, calculate `retry_after_ms` (the time until the oldest timestamp expires) and return `{:error, :rate_limited, retry_after_ms}`.
4.  **State Management:** Ensure the GenServer state is updated with the pruned list of timestamps.

**Context:**
```elixir
defmodule RateLimiter do
  @moduledoc """
  A GenServer that enforces per-key rate limits using a sliding window algorithm.

  Each key is tracked independently via a list of request timestamps.
  On every `check/4` call, timestamps outside the current window are pruned,
  and the request is allowed only if the remaining count is within the limit.

  Expired entries are garbage-collected on a configurable periodic sweep so the
  process never leaks memory for keys that stop receiving traffic.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = RateLimiter.start_link([])
      iex> {:ok, 4} = RateLimiter.check(pid, "user:1", 5, 1_000)
      iex> {:ok, 3} = RateLimiter.check(pid, "user:1", 5, 1_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the RateLimiter process and links it to the caller.

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
  Checks whether a request for `key` is allowed under the given limits.

  Returns `{:ok, remaining}` when the request is accepted, where `remaining`
  is the number of additional requests the caller may make in this window.

  Returns `{:error, :rate_limited, retry_after_ms}` when the limit has been
  reached.  `retry_after_ms` is the minimum wait (in milliseconds) before the
  oldest tracked request falls outside the window.
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
       # %{key => {[timestamp], window_ms}}
       keys: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    # TODO
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      state.keys
      |> Enum.reduce(%{}, fn {key, {timestamps, window_ms}}, acc ->
        window_start = now - window_ms
        active = Enum.filter(timestamps, fn ts -> ts > window_start end)

        # Drop the key entirely when no active timestamps remain.
        if active == [] do
          acc
        else
          Map.put(acc, key, {active, window_ms})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
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
```"