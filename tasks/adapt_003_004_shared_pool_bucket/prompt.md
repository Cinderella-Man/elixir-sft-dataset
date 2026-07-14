# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

Write me an Elixir GenServer module called `SharedPoolBucket` that implements **two-level** token-based rate limiting — each named bucket has its own capacity and refill rate, but all acquires also draw against a shared global pool that constrains the whole server.

The motivation: in multi-tenant systems (SaaS APIs, shared compute clusters), each tenant deserves their own fair allocation (so one tenant can't monopolize), but the infrastructure also has a hard system-wide throughput ceiling (database connections, bandwidth, etc.). A request succeeds only when *both* the tenant's per-key bucket AND the global pool have enough tokens. This is different from a hierarchical limiter (which has multiple tiers per individual key) — here the second level spans across all keys.

I need these functions in the public API:

- `SharedPoolBucket.start_link(opts)` to start the process. The global pool is configured at start time:
  - `:global_capacity` — pool maximum (required, positive integer)
  - `:global_refill_rate` — pool refill rate in tokens/sec (required, positive number)
  - `:clock` — zero-arity function returning current time in ms (default `fn -> System.monotonic_time(:millisecond) end`)
  - `:name` — optional process registration
  - `:cleanup_interval_ms` — periodic sweep interval (default 60_000)

- `SharedPoolBucket.acquire(server, bucket_name, key_capacity, key_refill_rate, tokens \\ 1)` — attempts to drain `tokens` from the named bucket AND from the global pool atomically. Both must have sufficient tokens or the request is rejected and **nothing is drained from either level**. Per-key buckets start full at `key_capacity` when first seen; the global pool starts full at `global_capacity` when the server starts.

  Both levels use the standard lazy-refill formula: `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. Apply the refill to both levels before evaluating the drain.

  Return values:
  - `{:ok, key_remaining, global_remaining}` on success, both as integer floors of the post-drain float balances.
  - `{:error, :key_empty, retry_after_ms}` if the per-key bucket doesn't have enough tokens (retry_after reflects how long until the per-key bucket has enough).
  - `{:error, :global_empty, retry_after_ms}` if the per-key bucket would have admitted but the global pool is insufficient (retry_after reflects the global shortage).
  - If both levels are short, return the **per-key** error first (a caller whose own tier is depleted shouldn't be given the false impression that the global pool is their blocker). This ordering matters — it's explicit in the semantics.

  `acquire/5` and `key_level/4` must validate their arguments with function
  guards: a non-positive `key_capacity`, non-positive `key_refill_rate`, or
  non-positive `tokens` matches no clause and raises `FunctionClauseError` —
  an invalid call must never drain tokens or create a bucket. A `retry_after_ms`
  is always at least 1 (a sub-millisecond shortage still reports 1 ms) and is
  rounded UP from the exact `deficit * 1000 / refill_rate` computation.

- `SharedPoolBucket.global_level(server)` — returns `{:ok, integer_remaining}` with the floor of the current global pool balance after applying the lazy refill.

- `SharedPoolBucket.key_level(server, bucket_name, key_capacity, key_refill_rate)` — returns `{:ok, integer_remaining}` for the specified per-key bucket (refilled lazily) or `{:ok, key_capacity}` if the bucket has never been seen. The capacity/refill arguments are needed because they're not stored at bucket-creation time — the bucket is defined per-acquire.

Per-bucket state (per key) must track the current token count (float), the last access timestamp, the last-known capacity, and the last-known refill rate. The global pool tracks its own token count (float) and last-refill timestamp in the top-level GenServer state (NOT in the buckets map).

Periodic cleanup via `Process.send_after` every `:cleanup_interval_ms` milliseconds. The sweep drops any per-key bucket whose projected free balance has refilled back to capacity (indistinguishable from a fresh bucket). The global pool is never dropped. Use the injectable clock, not wall time.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic
  timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup
  pass immediately — the same work the periodic timer performs.
