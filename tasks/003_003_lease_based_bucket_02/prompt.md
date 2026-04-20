Implement the private `refill_and_expire/2` helper function. This function serves as the single entry point for all bucket state transitions.

1. **Refill Logic:** Calculate the time elapsed since `bucket.last_update_at` and the current time `now`. Add tokens to the `free` balance based on the `refill_rate` (tokens per second), ensuring the balance does not exceed the bucket's `capacity`. 
2. **Lease Expiry:** Iterate through the `leases` map and remove any lease where the expiration timestamp is less than or equal to `now`. 
3. **Pessimistic Expiry:** It is critical that expired leases **do not** refund tokens to the `free` balance. They are treated as completed/consumed.
4. **Update State:** Return the updated bucket map with the new `free` balance, the updated `last_update_at` timestamp, and the filtered `leases` map.

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
  @spec acquire_lease(GenServer.server(), term(), pos_integer(), number(), pos_integer(), pos_integer()) ::
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
  def handle_call({:acquire_lease, bucket_name, capacity, refill_rate, tokens, timeout_ms}, _from, state) do
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

            {:reply, :ok,
             %{state | buckets: Map.put(state.buckets, bucket_name, new_bucket)}}
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
    # TODO
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