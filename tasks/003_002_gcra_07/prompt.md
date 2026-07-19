# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `schedule_cleanup` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `GcraLimiter` that implements rate limiting using the **Generic Cell Rate Algorithm (GCRA)**.

GCRA is the rate-limiting algorithm used in ATM networks and in modern systems like Redis-Cell. It's mathematically equivalent to a token bucket but uses a completely different state representation: instead of tracking `{tokens, last_refill_at}` per bucket, GCRA tracks a single scalar — the **Theoretical Arrival Time (TAT)**, which is the earliest wall-clock time at which the next request would be admitted if no burst were allowed.

I need these functions in the public API:

- `GcraLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `GcraLimiter.acquire(server, bucket_name, rate_per_sec, burst_size, tokens \\ 1)` which attempts to admit a request of `tokens` units for the named bucket. `rate_per_sec` is the steady-state rate (requests per second); `burst_size` is the maximum burst that's allowed above the steady state (analogous to bucket capacity in token-bucket terms).

  The algorithm works like this. Let `emission_interval = 1000 / rate_per_sec` (ms per single token at the steady rate). Let `delay_variation_tolerance = burst_size * emission_interval` (how far *before* the TAT we'll still admit a request — this is what allows bursts). For each `acquire`:

  1. Fetch the current TAT for the bucket (default: `now` if the bucket is brand new — a fresh bucket admits the full burst immediately).
  2. Compute `new_tat = max(now, tat) + tokens * emission_interval`.
  3. Compute `earliest_admit_time = new_tat - delay_variation_tolerance`.
  4. If `earliest_admit_time <= now`: accept the request. Store `new_tat` as the bucket's TAT. Return `{:ok, remaining}` where `remaining` is the equivalent "tokens left in the burst budget" — specifically `floor((delay_variation_tolerance - (new_tat - now)) / emission_interval)`.
  5. Otherwise: reject. Do NOT update TAT. Return `{:error, :rate_exceeded, retry_after_ms}` where `retry_after_ms = ceil(earliest_admit_time - now)`.

  Two pitfalls the model must avoid:
  - **Forgetting the `max(now, tat)` step**: if the bucket was idle (TAT is in the past), you must reset the baseline to `now`, or you'd "credit" the bucket for idle time beyond the burst tolerance and allow unbounded bursts after a long quiet period.
  - **Updating TAT on rejection**: a rejected request must not advance TAT, or repeated rejected calls would push TAT forward with no corresponding admits, starving legitimate retries.

Each bucket name must be tracked independently. Rate and burst parameters are passed per call (not configured at start_link), matching the original task's pattern.

You also need periodic cleanup via `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option, default 60_000). A bucket is safe to drop when its TAT is far enough in the past that an immediate acquire would behave identically to a fresh bucket — specifically, when `now - tat >= cleanup_idle_ms` (default 300_000ms, configurable via `:cleanup_idle_ms`). Use the injectable clock, not wall time.

The `remaining` value on success is an integer. The `retry_after_ms` value on rejection is a positive integer (minimum 1).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic
  timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup
  pass immediately — the same work the periodic timer performs.

## The module with `schedule_cleanup` missing

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
    now = state.clock.()
    idle_threshold = state.cleanup_idle_ms

    cleaned =
      Enum.reduce(state.buckets, %{}, fn {bucket, tat}, acc ->
        # If TAT is far enough in the past that the bucket would behave
        # identically to a fresh one, drop it.
        if now - tat >= idle_threshold do
          acc
        else
          Map.put(acc, bucket, tat)
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | buckets: cleaned}}
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

  defp schedule_cleanup(:infinity) do
    # TODO
  end
end
```

Give me only the complete implementation of `schedule_cleanup` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
