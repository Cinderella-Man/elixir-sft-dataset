# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

Write me an Elixir GenServer module called `LeaseBucket` that implements a token-based leaky bucket where tokens are **reserved via leases** rather than consumed immediately.

The motivation: in many real-world systems (API quota accounting, connection pools, compute resource allocation), you don't know at request-start whether the operation will succeed, fail, or be cancelled. A consume-on-acquire bucket over-counts cancelled operations. A lease-based bucket lets you *reserve* tokens at operation start and then either **complete** the lease (tokens permanently consumed) or **cancel** the lease (tokens refunded to the bucket). Leases that exceed a timeout are pessimistically treated as completed, so a crashed caller can't leak reservations indefinitely.

I need these functions in the public API:

- `LeaseBucket.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `LeaseBucket.acquire_lease(server, bucket_name, capacity, refill_rate, tokens, lease_timeout_ms)` — attempts to reserve `tokens` from the named bucket for up to `lease_timeout_ms` milliseconds. A bucket that has not been seen before starts with its free balance at full `capacity`. Refills are computed lazily on every call using `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. On success, deduct the tokens from the bucket's free balance, record the lease, and return `{:ok, lease_id, remaining}` where `lease_id` is an opaque identifier and `remaining` is the floor of the free balance after the reservation. On failure, return `{:error, :empty, retry_after_ms}` where `retry_after_ms` is a positive integer estimating the milliseconds until enough tokens refill. Guard the public function head so that out-of-contract arguments raise `FunctionClauseError` rather than being handled at runtime: `capacity`, `tokens`, and `lease_timeout_ms` must be positive integers, `refill_rate` a positive number, and `tokens` must not exceed `capacity`.

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

## The buggy module

```elixir
defmodule LeaseBucket do
  @moduledoc """
  A GenServer-based token bucket where tokens are **reserved via leases**
  rather than consumed immediately.

  On `acquire_lease/6`, tokens are deducted from the bucket's free balance
  and a lease record is created with an expiry timestamp.  The caller later
  invokes `release/4` with either `:completed` (tokens stay consumed) or
  `:cancelled` (tokens refunded).  A lease whose deadline passes without an
  explicit release is pessimistically treated as `:completed` — tokens are
  **not** refunded — to prevent clients from exploiting unreleased leases to
  game the rate budget.

  Per-bucket state:

      %{
        free: float,                        # current free token balance (float)
        capacity: pos_integer,              # configured max
        refill_rate: float,                 # tokens per second
        last_update_at: integer,            # ms, for lazy refill math
        leases: %{lease_id => {tokens, expires_at}}
      }

  Refill math is the standard lazy formula: on every touch of a bucket,
  `free = min(capacity, free + elapsed_ms * refill_rate / 1000)` and
  `last_update_at = now`.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
    * `:cleanup_interval_ms`  – sweep interval (default 60_000)

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
  Reserves `tokens` from the named bucket for up to `lease_timeout_ms`.

  Returns `{:ok, lease_id, remaining}` on success or
  `{:error, :empty, retry_after_ms}` when the bucket doesn't have enough
  free tokens.
  """
  @spec acquire_lease(
          GenServer.server(),
          term(),
          pos_integer(),
          number(),
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, reference(), non_neg_integer()}
          | {:error, :empty, pos_integer()}
  def acquire_lease(server, bucket, capacity, refill_rate, tokens, lease_timeout_ms)
      when is_integer(capacity) and capacity > 0 and
             is_number(refill_rate) and refill_rate > 0 and
             is_integer(tokens) and tokens > 1 and tokens <= capacity and
             is_integer(lease_timeout_ms) and lease_timeout_ms > 0 do
    GenServer.call(
      server,
      {:acquire_lease, bucket, capacity, refill_rate * 1.0, tokens, lease_timeout_ms}
    )
  end

  @doc """
  Releases a lease previously returned by `acquire_lease/6`.

  `outcome` is `:completed` (tokens permanently consumed) or `:cancelled`
  (tokens refunded to the bucket).  Returns `:ok` on success or
  `{:error, :unknown_lease}` if the lease has already been released or has
  expired.
  """
  @spec release(GenServer.server(), term(), reference(), :completed | :cancelled) ::
          :ok | {:error, :unknown_lease}
  def release(server, bucket, lease_id, outcome) when outcome in [:completed, :cancelled] do
    GenServer.call(server, {:release, bucket, lease_id, outcome})
  end

  @doc """
  Returns the number of currently active (not yet released or expired)
  leases on a bucket.  Unknown buckets return `{:ok, 0}`.
  """
  @spec active_leases(GenServer.server(), term()) :: {:ok, non_neg_integer()}
  def active_leases(server, bucket) do
    GenServer.call(server, {:active_leases, bucket})
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
       buckets: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call(
        {:acquire_lease, bucket_name, capacity, refill_rate, tokens, timeout_ms},
        _from,
        state
      ) do
    now = state.clock.()

    bucket = get_bucket(state, bucket_name, capacity, refill_rate, now)
    bucket = refill_and_expire(bucket, now)

    if bucket.free >= tokens do
      lease_id = make_ref()
      lease = {tokens, now + timeout_ms}

      new_bucket = %{
        bucket
        | free: bucket.free - tokens,
          leases: Map.put(bucket.leases, lease_id, lease)
      }

      remaining = trunc(new_bucket.free)

      {:reply, {:ok, lease_id, remaining},
       %{state | buckets: Map.put(state.buckets, bucket_name, new_bucket)}}
    else
      # Not enough free tokens.  Compute how long until the deficit refills.
      deficit = tokens - bucket.free
      retry_after = ceil_positive(deficit * 1000 / refill_rate)

      # Persist the refill-expire update even on failure.
      {:reply, {:error, :empty, retry_after},
       %{state | buckets: Map.put(state.buckets, bucket_name, bucket)}}
    end
  end

  def handle_call({:release, bucket_name, lease_id, outcome}, _from, state) do
    case Map.fetch(state.buckets, bucket_name) do
      :error ->
        {:reply, {:error, :unknown_lease}, state}

      {:ok, bucket} ->
        now = state.clock.()
        bucket = refill_and_expire(bucket, now)

        case Map.fetch(bucket.leases, lease_id) do
          :error ->
            # Lease was either never issued, already released, or expired
            # during refill_and_expire above.
            {:reply, {:error, :unknown_lease},
             %{state | buckets: Map.put(state.buckets, bucket_name, bucket)}}

          {:ok, {tokens, _expires_at}} ->
            new_bucket =
              case outcome do
                :completed ->
                  %{bucket | leases: Map.delete(bucket.leases, lease_id)}

                :cancelled ->
                  refunded = min(bucket.capacity * 1.0, bucket.free + tokens)

                  %{
                    bucket
                    | free: refunded,
                      leases: Map.delete(bucket.leases, lease_id)
                  }
              end

            {:reply, :ok, %{state | buckets: Map.put(state.buckets, bucket_name, new_bucket)}}
        end
    end
  end

  def handle_call({:active_leases, bucket_name}, _from, state) do
    case Map.fetch(state.buckets, bucket_name) do
      :error ->
        {:reply, {:ok, 0}, state}

      {:ok, bucket} ->
        now = state.clock.()

        # Compute the up-to-date count WITHOUT persisting anything: the
        # contract's touch-list (acquire, release, the cleanup sweep) is
        # exhaustive — a query must never be the operation that mutates a
        # bucket. Expiry/refill are recomputed identically by the next
        # real touch, so nothing is lost by not storing them here.
        %{leases: live} = refill_and_expire(bucket, now)

        {:reply, {:ok, map_size(live)}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      Enum.reduce(state.buckets, %{}, fn {name, bucket}, acc ->
        bucket = refill_and_expire(bucket, now)

        # A bucket with no leases and full free balance is indistinguishable
        # from a never-seen one — safe to drop.
        if map_size(bucket.leases) == 0 and bucket.free >= bucket.capacity do
          acc
        else
          Map.put(acc, name, bucket)
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | buckets: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp get_bucket(state, bucket_name, capacity, refill_rate, now) do
    case Map.fetch(state.buckets, bucket_name) do
      {:ok, bucket} ->
        # Allow the caller to update refill_rate / capacity mid-stream.
        %{bucket | capacity: capacity, refill_rate: refill_rate}

      :error ->
        # Fresh bucket starts full.
        %{
          free: capacity * 1.0,
          capacity: capacity,
          refill_rate: refill_rate,
          last_update_at: now,
          leases: %{}
        }
    end
  end

  # Single entry point for all bucket state transitions.  Applies elapsed-time
  # refill math AND expires any lease whose deadline has passed (expired leases
  # are treated as :completed — NO token refund).
  defp refill_and_expire(bucket, now) do
    elapsed = now - bucket.last_update_at
    added = elapsed * bucket.refill_rate / 1000
    new_free = min(bucket.capacity * 1.0, bucket.free + added)

    # Expire leases where expires_at <= now.  Tokens are NOT refunded.
    active_leases =
      bucket.leases
      |> Enum.reject(fn {_id, {_tokens, expires_at}} -> expires_at <= now end)
      |> Enum.into(%{})

    %{bucket | free: new_free, last_update_at: now, leases: active_leases}
  end

  # ceil that always returns a positive integer, suitable for retry_after_ms.
  defp ceil_positive(x) when is_number(x) do
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

## Failing test report

```
8 of 21 test(s) failed:

  * test release :completed keeps tokens consumed
      no function clause matching in LeaseBucket.acquire_lease/6

  * test release of unknown lease returns {:error, :unknown_lease}
      no function clause matching in LeaseBucket.acquire_lease/6

  * test free balance refills lazily between calls
      no function clause matching in LeaseBucket.acquire_lease/6

  * test refill caps at capacity
      no function clause matching in LeaseBucket.acquire_lease/6

  (…4 more)
```
