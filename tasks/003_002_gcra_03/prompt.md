Implement the `handle_info/2` callback for the `:cleanup` message. 

First, retrieve the current time using the clock function stored in the state.

Iterate through the `buckets` map in the state and remove any stale buckets. A bucket should be dropped if the difference between the current time and its TAT is greater than or equal to `state.cleanup_idle_ms`. Keep all other buckets.

Once the map is filtered, schedule the next cleanup cycle by passing `state.cleanup_interval_ms` to the private `schedule_cleanup/1` helper.

Finally, return a `{:noreply, updated_state}` tuple where the state contains the newly filtered map of buckets.

```elixir
defmodule GcraLimiter do
  @moduledoc """
  A GenServer that implements rate limiting using the Generic Cell Rate
  Algorithm (GCRA).

  GCRA tracks a single scalar per bucket — the **Theoretical Arrival Time**
  (TAT), which represents the earliest wall-clock time at which the next
  request would be admitted if no burst were allowed.  Admitting a request
  pushes the TAT forward by one emission interval per token consumed; bursts
  are permitted by admitting requests up to `delay_variation_tolerance`
  milliseconds *before* the current TAT.

  This is mathematically equivalent to a token bucket but uses a completely
  different representation — a single float per bucket instead of
  `{tokens, last_refill_at}`.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – periodic sweep interval (default 60_000)
    * `:cleanup_idle_ms`      – drop buckets whose TAT is this far in the past
                                (default 300_000)

  ## Examples

      iex> {:ok, pid} = GcraLimiter.start_link([])
      iex> {:ok, 4} = GcraLimiter.acquire(pid, "user:1", 5.0, 5)
      iex> {:ok, 3} = GcraLimiter.acquire(pid, "user:1", 5.0, 5)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Attempts to admit a request of `tokens` units for `bucket_name`.

  Returns `{:ok, remaining}` when admitted, where `remaining` is the number
  of additional tokens that could still be immediately admitted before the
  burst budget runs out.

  Returns `{:error, :rate_exceeded, retry_after_ms}` when the request would
  exceed the allowed burst.  TAT is not mutated on rejection — back-to-back
  rejected calls do not starve the caller of future admits.
  """
  @spec acquire(GenServer.server(), term(), number(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_exceeded, pos_integer()}
  def acquire(server, bucket_name, rate_per_sec, burst_size, tokens \\ 1)
      when is_number(rate_per_sec) and rate_per_sec > 0 and
           is_integer(burst_size) and burst_size > 0 and
           is_integer(tokens) and tokens > 0 do
    GenServer.call(server, {:acquire, bucket_name, rate_per_sec, burst_size, tokens})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000
  @default_cleanup_idle_ms 300_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    cleanup_idle = Keyword.get(opts, :cleanup_idle_ms, @default_cleanup_idle_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{bucket_name => tat_ms (float)}
       buckets: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval,
       cleanup_idle_ms: cleanup_idle
     }}
  end

  @impl true
  def handle_call({:acquire, bucket, rate_per_sec, burst, tokens}, _from, state) do
    now = state.clock.()

    # Derived constants.
    emission_interval = 1000 / rate_per_sec
    dvt = burst * emission_interval

    # Fresh bucket starts at TAT = now (full burst immediately available).
    tat = Map.get(state.buckets, bucket, now * 1.0)

    # Advance the TAT baseline if the bucket has been idle past it —
    # without this `max`, idle time would be credited beyond `burst`.
    new_tat = max(now, tat) + tokens * emission_interval
    earliest_admit = new_tat - dvt

    if earliest_admit <= now do
      # Accept.  The remaining burst headroom, expressed in tokens, is how
      # much slack we still have between (new_tat - now) and DVT.
      slack = dvt - (new_tat - now)
      remaining = max(trunc(slack / emission_interval), 0)

      {:reply, {:ok, remaining}, %{state | buckets: Map.put(state.buckets, bucket, new_tat)}}
    else
      # Reject.  Crucially, do NOT update TAT — repeated rejects must not
      # push the admit frontier further into the future.
      retry_after = ceil_positive(earliest_admit - now)
      {:reply, {:error, :rate_exceeded, retry_after}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    # TODO
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Ceiling that always returns a positive integer, suitable for retry_after.
  defp ceil_positive(x) do
    c = trunc(x)
    c = if c < x, do: c + 1, else: c
    max(c, 1)
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```