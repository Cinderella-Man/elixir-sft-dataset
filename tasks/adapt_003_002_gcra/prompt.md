# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule LeakyBucket do
  @moduledoc """
  A token-based leaky bucket rate limiter implemented as a GenServer.

  Tokens are refilled lazily on each `acquire/5` call based on elapsed time,
  rather than via per-bucket timers. A periodic cleanup sweep removes buckets
  that haven't been accessed within a configurable TTL to prevent memory leaks.
  """

  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Starts the LeakyBucket GenServer.

  ## Options

    * `:clock` — zero-arity function returning current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` — optional name for process registration.
    * `:cleanup_interval_ms` — how often the cleanup sweep runs (default 60_000).
    * `:cleanup_ttl_ms` — buckets idle longer than this are evicted (default 300_000).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = extract_gen_opts(opts)
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Attempts to drain `tokens` from the named bucket.

  Returns `{:ok, remaining}` on success or `{:error, :empty, retry_after_ms}`
  when insufficient tokens are available.

  A bucket that has never been seen before starts full at `capacity`.
  """
  @spec acquire(GenServer.server(), term(), pos_integer(), number(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :empty, pos_integer()}
  def acquire(server, bucket_name, capacity, refill_rate, tokens \\ 1) do
    GenServer.call(server, {:acquire, bucket_name, capacity, refill_rate, tokens})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────────────────────

  defmodule State do
    @moduledoc false
    @enforce_keys [:clock, :cleanup_interval_ms, :cleanup_ttl_ms]
    defstruct [:clock, :cleanup_interval_ms, :cleanup_ttl_ms, buckets: %{}]
  end

  defmodule Bucket do
    @moduledoc false
    @enforce_keys [:tokens, :last_access]
    defstruct [:tokens, :last_access]
  end

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, 60_000)
    cleanup_ttl_ms = Keyword.get(opts, :cleanup_ttl_ms, 300_000)

    state = %State{
      clock: clock,
      cleanup_interval_ms: cleanup_interval_ms,
      cleanup_ttl_ms: cleanup_ttl_ms
    }

    schedule_cleanup(cleanup_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:acquire, bucket_name, capacity, refill_rate, tokens},
        _from,
        %State{} = state
      ) do
    now = state.clock.()

    bucket =
      case Map.get(state.buckets, bucket_name) do
        nil ->
          # Brand-new bucket starts full at capacity.
          %Bucket{tokens: capacity * 1.0, last_access: now}

        existing ->
          refill(existing, now, capacity, refill_rate)
      end

    if bucket.tokens >= tokens do
      drained = %Bucket{bucket | tokens: bucket.tokens - tokens, last_access: now}
      new_state = %State{state | buckets: Map.put(state.buckets, bucket_name, drained)}
      {:reply, {:ok, floor(drained.tokens)}, new_state}
    else
      # How many tokens are we short?
      deficit = tokens - bucket.tokens
      # Time to refill the deficit at the given rate (tokens/sec → ms).
      retry_after_ms = ceil(deficit / refill_rate * 1000)

      # Still update last_access so the refilled tokens aren't lost and the
      # bucket isn't prematurely evicted by cleanup.
      touched = %Bucket{bucket | last_access: now}
      new_state = %State{state | buckets: Map.put(state.buckets, bucket_name, touched)}

      {:reply, {:error, :empty, retry_after_ms}, new_state}
    end
  end

  @impl true
  def handle_info(:cleanup, %State{} = state) do
    now = state.clock.()

    buckets =
      state.buckets
      |> Enum.reject(fn {_name, bucket} ->
        now - bucket.last_access > state.cleanup_ttl_ms
      end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %State{state | buckets: buckets}}
  end

  # Catch-all so unexpected messages don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private helpers ─────────────────────────────────────────────────────────────────────────

  defp refill(%Bucket{} = bucket, now, capacity, refill_rate) do
    elapsed_ms = max(now - bucket.last_access, 0)
    new_tokens = min(capacity * 1.0, bucket.tokens + elapsed_ms * refill_rate / 1000)
    %Bucket{bucket | tokens: new_tokens}
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp extract_gen_opts(opts) do
    {name_opts, rest} = Keyword.split(opts, [:name])

    gen_opts =
      case Keyword.get(name_opts, :name) do
        nil -> []
        name -> [name: name]
      end

    {gen_opts, rest}
  end
end
```

## New specification

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
