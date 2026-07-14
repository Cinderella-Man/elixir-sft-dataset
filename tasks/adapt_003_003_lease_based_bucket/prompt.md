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

Write me an Elixir GenServer module called `LeaseBucket` that implements a token-based leaky bucket where tokens are **reserved via leases** rather than consumed immediately.

The motivation: in many real-world systems (API quota accounting, connection pools, compute resource allocation), you don't know at request-start whether the operation will succeed, fail, or be cancelled. A consume-on-acquire bucket over-counts cancelled operations. A lease-based bucket lets you *reserve* tokens at operation start and then either **complete** the lease (tokens permanently consumed) or **cancel** the lease (tokens refunded to the bucket). Leases that exceed a timeout are pessimistically treated as completed, so a crashed caller can't leak reservations indefinitely.

I need these functions in the public API:

- `LeaseBucket.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `LeaseBucket.acquire_lease(server, bucket_name, capacity, refill_rate, tokens, lease_timeout_ms)` — attempts to reserve `tokens` from the named bucket for up to `lease_timeout_ms` milliseconds. Refills are computed lazily on every call using `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. On success, deduct the tokens from the bucket's free balance, record the lease, and return `{:ok, lease_id, remaining}` where `lease_id` is an opaque identifier and `remaining` is the floor of the free balance after the reservation. On failure, return `{:error, :empty, retry_after_ms}`.

- `LeaseBucket.release(server, bucket_name, lease_id, outcome)` where outcome is `:completed` or `:cancelled`.
  - `:completed` — the operation succeeded; tokens stay consumed. Just remove the lease from tracking.
  - `:cancelled` — the operation failed or was aborted; refund the tokens to the bucket's free balance (capped at capacity). Remove the lease.
  - If `lease_id` doesn't exist (already released or expired), return `{:error, :unknown_lease}` without mutating state. Otherwise return `:ok`.

- `LeaseBucket.active_leases(server, bucket_name)` — returns `{:ok, count}` with the number of currently outstanding (not yet released or expired) leases for the bucket, or `{:ok, 0}` if the bucket is unknown.

The bucket's free balance must be tracked as a float (for fractional refill math); the `remaining` value returned on acquire is the floor of the float.

**Lease expiry is the trickiest part.** Every time any operation touches a bucket (`acquire_lease`, `release`, or the periodic cleanup sweep), the bucket must first expire any of its leases whose `expires_at <= now`. Expired leases are **treated as `:completed`** — tokens are NOT refunded. This is the pessimistic choice: a caller who crashes or forgets to release should not have their quota automatically returned, because that would create an exploit where clients can reserve tokens indefinitely by never releasing them. The lease tracking entry is simply removed. (But by the time we're in acquire/release/cleanup, the refill clock has been advanced, so those consumed tokens will refill naturally over time like any other completed work.)

Lease IDs should be opaque and globally unique across the server. A monotonic counter formatted as a reference or a binary is fine. Store lease data per bucket.

Periodic cleanup via `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms`, default 60_000). The cleanup sweep should (a) expire any lease whose `expires_at <= now`, and (b) drop any bucket whose free balance has refilled back to `capacity` AND whose active lease count is zero — such a bucket is indistinguishable from a fresh one.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic
  timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup
  pass immediately — the same work the periodic timer performs.

- Concretely, the `lease_id` returned by `acquire_lease` must be an Erlang
  reference created with `make_ref/0` — it must satisfy `is_reference/1`. Do
  not use a counter formatted as a binary or integer.
