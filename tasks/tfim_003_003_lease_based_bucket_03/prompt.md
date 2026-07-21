# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
             is_integer(tokens) and tokens > 0 and tokens <= capacity and
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
        bucket = refill_and_expire(bucket, now)

        {:reply, {:ok, map_size(bucket.leases)},
         %{state | buckets: Map.put(state.buckets, bucket_name, bucket)}}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule LeaseBucketTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      LeaseBucket.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    %{lb: pid}
  end

  # -------------------------------------------------------
  # Basic acquire / release
  # -------------------------------------------------------

  test "acquire_lease reserves tokens and returns a lease id", %{lb: lb} do
    assert {:ok, lease_id, 7} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)
    assert is_reference(lease_id)

    assert {:ok, 1} = LeaseBucket.active_leases(lb, "k")
  end

  test "rejects acquire when tokens exceed free balance", %{lb: lb} do
    # TODO
  end

  # -------------------------------------------------------
  # Release semantics — the defining behavior
  # -------------------------------------------------------

  test "release :cancelled refunds the tokens", %{lb: lb} do
    assert {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :cancelled)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Full balance restored — can take another 5-token lease
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 5, 60_000)
  end

  test "release :completed keeps tokens consumed", %{lb: lb} do
    assert {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Balance is NOT refunded — only 2 tokens free
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
    assert {:ok, _, 1} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)
  end

  test "release of unknown lease returns {:error, :unknown_lease}", %{lb: lb} do
    # Unknown bucket
    assert {:error, :unknown_lease} =
             LeaseBucket.release(lb, "nope", make_ref(), :cancelled)

    # Known bucket, unknown lease
    LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)

    assert {:error, :unknown_lease} =
             LeaseBucket.release(lb, "k", make_ref(), :cancelled)
  end

  test "double-release returns {:error, :unknown_lease} on second call", %{lb: lb} do
    {:ok, lease_id, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 2, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :cancelled)
    assert {:error, :unknown_lease} = LeaseBucket.release(lb, "k", lease_id, :cancelled)
  end

  # -------------------------------------------------------
  # Lease expiry — tokens are NOT refunded
  # -------------------------------------------------------

  test "expired leases disappear without refunding tokens", %{lb: lb} do
    # Acquire a lease with a 1-second timeout
    {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 1_000)
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "k")

    # Advance past lease expiry.  The next operation must expire the lease.
    Clock.advance(1_500)

    # active_leases triggers the expiry sweep for this bucket
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Explicitly releasing the expired lease should fail
    assert {:error, :unknown_lease} = LeaseBucket.release(lb, "k", lease_id, :cancelled)

    # Tokens are NOT refunded — but some will have refilled due to elapsed time.
    # At 1.0 tokens/sec with 1.5s elapsed, the free balance went from 2 to 3.5.
    # Acquiring 4 should still fail (only 3.5 free, floor = 3)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 4, 60_000)
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
  end

  test "acquire/release trigger bucket-level expiry of OTHER leases", %{lb: lb} do
    # Short-timeout lease
    {:ok, _l1, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 500)

    # Long-timeout lease
    {:ok, l2, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)

    assert {:ok, 2} = LeaseBucket.active_leases(lb, "k")

    # Advance past the short lease's expiry but within the long lease's
    Clock.advance(1_000)

    # Any operation should expire the short lease
    assert :ok = LeaseBucket.release(lb, "k", l2, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")
  end

  # -------------------------------------------------------
  # Refill math (standard token bucket, on the free balance)
  # -------------------------------------------------------

  test "free balance refills lazily between calls", %{lb: lb} do
    # Drain to 0 by acquiring and then never releasing
    {:ok, _lease, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 5, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)

    # Advance 2 seconds at 1 token/sec — free balance goes from 0 to 2
    Clock.advance(2_000)

    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 2, 60_000)
  end

  test "refill caps at capacity", %{lb: lb} do
    # Acquire and cancel to leave bucket intact at full
    {:ok, l, _} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 3, 60_000)
    LeaseBucket.release(lb, "k", l, :cancelled)

    # Idle for a long time — balance should cap at 3, not accumulate
    Clock.advance(100_000)

    # Should still only admit 3, not more
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 3, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 1, 60_000)
  end

  # -------------------------------------------------------
  # Multiple concurrent leases on the same bucket
  # -------------------------------------------------------

  test "multiple outstanding leases are tracked independently", %{lb: lb} do
    {:ok, l1, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)
    {:ok, l2, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 4, 60_000)
    {:ok, l3, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 2, 60_000)

    assert {:ok, 3} = LeaseBucket.active_leases(lb, "k")

    # Cancelling l2 refunds 4 tokens
    assert :ok = LeaseBucket.release(lb, "k", l2, :cancelled)
    assert {:ok, 2} = LeaseBucket.active_leases(lb, "k")

    # 4 tokens refunded + 1 still free = 5 free
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 5, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", l1, :completed)
    assert :ok = LeaseBucket.release(lb, "k", l3, :cancelled)
  end

  # -------------------------------------------------------
  # Bucket independence
  # -------------------------------------------------------

  test "different buckets are completely isolated", %{lb: lb} do
    {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "a", 3, 1.0, 3, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "a", 3, 1.0, 1, 60_000)

    # Bucket "b" is untouched
    assert {:ok, _, 2} = LeaseBucket.acquire_lease(lb, "b", 3, 1.0, 1, 60_000)
    assert {:ok, _, 1} = LeaseBucket.acquire_lease(lb, "b", 3, 1.0, 1, 60_000)
  end

  # -------------------------------------------------------
  # active_leases on unknown bucket
  # -------------------------------------------------------

  test "active_leases returns 0 for unknown bucket", %{lb: lb} do
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "never_seen")
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup drops fully-refilled buckets with no active leases", %{lb: lb} do
    # Create 50 buckets, each with one short lease that will expire
    for i <- 1..50 do
      LeaseBucket.acquire_lease(lb, "k:#{i}", 2, 10.0, 2, 100)
    end

    # Advance far enough for leases to expire AND buckets to refill
    Clock.advance(10_000)

    send(lb, :cleanup)

    # A synchronous call is served only after the cleanup message is handled,
    # so this both waits for the sweep and reads an untouched bucket name.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "sentinel")

    # A swept bucket is indistinguishable from a fresh one: no active leases
    # and a free balance back at full capacity.
    for i <- 1..50 do
      assert {:ok, 0} = LeaseBucket.active_leases(lb, "k:#{i}")
      assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k:#{i}", 2, 10.0, 2, 100)
    end
  end

  test "cleanup keeps buckets with active leases", %{lb: lb} do
    # Long-running lease keeps the bucket alive
    {:ok, l, _} = LeaseBucket.acquire_lease(lb, "alive", 5, 1.0, 2, 3_600_000)

    # Short lease expires
    LeaseBucket.acquire_lease(lb, "gone", 2, 10.0, 1, 100)
    Clock.advance(10_000)

    send(lb, :cleanup)

    # A synchronous call is served only after the cleanup message is handled.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "sentinel")

    # The long lease survived the sweep: it is still counted and still
    # releasable by its id.
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "alive")
    assert :ok = LeaseBucket.release(lb, "alive", l, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "alive")

    # The bucket whose only lease expired is back to fresh behavior.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "gone")
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "gone", 2, 10.0, 2, 100)
  end

  # -------------------------------------------------------
  # Public-head contract: out-of-contract arguments raise
  # -------------------------------------------------------

  test "acquire_lease raises FunctionClauseError on out-of-contract arguments", %{lb: lb} do
    # capacity must be a positive integer
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 0, 1.0, 1, 60_000)
    end

    # tokens must be a positive integer
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 0, 60_000)
    end

    # refill_rate must be a positive number
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 0.0, 1, 60_000)
    end

    # lease_timeout_ms must be a positive integer
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 0)
    end

    # tokens must not exceed capacity
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 6, 60_000)
    end
  end

  # -------------------------------------------------------
  # retry_after_ms is a real backoff estimate, not a placeholder
  # -------------------------------------------------------

  test "retry_after_ms estimates the milliseconds until the deficit refills", %{lb: lb} do
    # Capacity 5, reserve 3 → 2 tokens free.
    assert {:ok, _, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    # A second 3-token request has a 1-token deficit; at 1.0 token/sec that
    # is 1000 ms until enough tokens refill.
    assert {:error, :empty, 1000} =
             LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
  end

  # -------------------------------------------------------
  # Periodic cleanup fires on its own timer (no external trigger)
  # -------------------------------------------------------

  test "periodic cleanup fires automatically on a real interval" do
    # A real, short interval means the sweep runs on its own timer, driven by
    # the default wall-clock. The lease deadline passes on its own, and an
    # automatic sweep returns the bucket to fresh behaviour.
    server = start_supervised!({LeaseBucket, cleanup_interval_ms: 25})

    {:ok, _lease, 0} = LeaseBucket.acquire_lease(server, "k", 2, 1000.0, 2, 20)

    # Poll a generous window (well over 20× the interval) for the automatic
    # outcome, never sending :cleanup ourselves.
    deadline = System.monotonic_time(:millisecond) + 1_000

    assert :ok =
             wait_until(
               fn -> LeaseBucket.active_leases(server, "k") == {:ok, 0} end,
               deadline
             )

    # Back to fresh: a full-capacity reservation succeeds again.
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(server, "k", 2, 1000.0, 2, 20)
  end

  defp wait_until(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(5)
        wait_until(fun, deadline)
    end
  end
end
```
