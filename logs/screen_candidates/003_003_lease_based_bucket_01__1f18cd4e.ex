defmodule LeaseBucket do
  @moduledoc """
  A token-based leaky bucket where tokens are *reserved via leases* rather than
  consumed immediately.

  In many real-world systems (API quota accounting, connection pools, compute
  resource allocation) you cannot know at request-start whether an operation
  will succeed, fail, or be cancelled. A consume-on-acquire bucket over-counts
  cancelled operations. This module instead lets a caller *reserve* tokens at
  operation start via `acquire_lease/6` and then either:

    * **complete** the lease — tokens stay permanently consumed, or
    * **cancel** the lease — tokens are refunded to the bucket's free balance.

  Leases carry a timeout. A lease whose `expires_at` has passed is treated
  *pessimistically as completed*: its tokens are **not** refunded. This prevents
  an exploit where a caller reserves tokens and simply never releases them. The
  refill clock still advances, so consumed tokens replenish naturally over time.

  ## Buckets

  Buckets are created lazily on first `acquire_lease/6` and identified by an
  arbitrary term. A bucket tracks its `capacity`, `refill_rate` (tokens/second),
  a floating-point free balance (for fractional refill math), the last time it
  was refilled, and the set of outstanding leases.

  Refills are computed lazily on every operation that touches a bucket:

      new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)

  Every touching operation (`acquire_lease/6`, `release/4`, and the periodic
  cleanup sweep) first expires any lease whose `expires_at <= now`.

  ## Cleanup

  A periodic sweep (default every `60_000` ms, configurable via
  `:cleanup_interval_ms`, or `:infinity` to disable) expires stale leases and
  drops any bucket that has refilled back to `capacity` with zero active leases,
  since such a bucket is indistinguishable from a fresh one. Sending the process
  a bare `:cleanup` message performs one such pass immediately.
  """

  use GenServer

  @type server :: GenServer.server()
  @type bucket_name :: term()
  @type outcome :: :completed | :cancelled

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the `LeaseBucket` server.

  Options:

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:cleanup_interval_ms` — interval between periodic cleanup sweeps, in
      milliseconds, or `:infinity` to never schedule one. Defaults to `60_000`.
    * `:name` — optional `GenServer` name registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Attempts to reserve `tokens` from `bucket_name` for up to `lease_timeout_ms`.

  The bucket is created (full, at `capacity`) on first use. Refills are computed
  lazily before the reservation is attempted.

  On success returns `{:ok, lease_id, remaining}` where `lease_id` is an opaque
  `t:reference/0` and `remaining` is the floor of the free balance after the
  reservation. On failure returns `{:error, :empty, retry_after_ms}` where
  `retry_after_ms` is an estimate of when enough tokens will have refilled (or
  `:infinity` when the request can never be satisfied).
  """
  @spec acquire_lease(server(), bucket_name(), number(), number(), number(),
          non_neg_integer()) ::
          {:ok, reference(), integer()}
          | {:error, :empty, non_neg_integer() | :infinity}
  def acquire_lease(server, bucket_name, capacity, refill_rate, tokens, lease_timeout_ms) do
    GenServer.call(
      server,
      {:acquire, bucket_name, capacity, refill_rate, tokens, lease_timeout_ms}
    )
  end

  @doc """
  Releases a previously acquired lease.

  `outcome` is either:

    * `:completed` — the operation succeeded; tokens stay consumed.
    * `:cancelled` — the operation failed or was aborted; tokens are refunded to
      the bucket's free balance (capped at capacity).

  Expiry runs first, so a lease that has already timed out (and was therefore
  treated as completed) is reported as unknown. Returns `:ok` on success, or
  `{:error, :unknown_lease}` if the lease does not exist.
  """
  @spec release(server(), bucket_name(), reference(), outcome()) ::
          :ok | {:error, :unknown_lease}
  def release(server, bucket_name, lease_id, outcome)
      when outcome in [:completed, :cancelled] do
    GenServer.call(server, {:release, bucket_name, lease_id, outcome})
  end

  @doc """
  Returns `{:ok, count}` with the number of currently outstanding leases (not yet
  released or expired) for `bucket_name`, or `{:ok, 0}` for an unknown bucket.
  """
  @spec active_leases(server(), bucket_name()) :: {:ok, non_neg_integer()}
  def active_leases(server, bucket_name) do
    GenServer.call(server, {:active_leases, bucket_name})
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    interval = Keyword.get(opts, :cleanup_interval_ms, 60_000)
    state = %{clock: clock, cleanup_interval_ms: interval, buckets: %{}}
    schedule_cleanup(interval)
    {:ok, state}
  end

  @impl true
  def handle_call(
        {:acquire, name, capacity, refill_rate, tokens, timeout},
        _from,
        state
      ) do
    now = state.clock.()

    bucket =
      case Map.fetch(state.buckets, name) do
        {:ok, existing} -> %{existing | capacity: capacity, refill_rate: refill_rate}
        :error -> new_bucket(capacity, refill_rate, now)
      end
      |> touch(now)

    if bucket.free >= tokens do
      lease_id = make_ref()
      lease = %{tokens: tokens, expires_at: now + timeout}
      free = bucket.free - tokens
      bucket = %{bucket | free: free, leases: Map.put(bucket.leases, lease_id, lease)}
      {:reply, {:ok, lease_id, floor(free)}, put_bucket(state, name, bucket)}
    else
      retry = retry_after(bucket, tokens)
      {:reply, {:error, :empty, retry}, put_bucket(state, name, bucket)}
    end
  end

  def handle_call({:release, name, lease_id, outcome}, _from, state) do
    now = state.clock.()

    case Map.fetch(state.buckets, name) do
      :error ->
        {:reply, {:error, :unknown_lease}, state}

      {:ok, bucket} ->
        bucket = touch(bucket, now)

        case Map.fetch(bucket.leases, lease_id) do
          :error ->
            {:reply, {:error, :unknown_lease}, put_bucket(state, name, bucket)}

          {:ok, lease} ->
            free =
              case outcome do
                :cancelled -> min(bucket.capacity, bucket.free + lease.tokens) * 1.0
                :completed -> bucket.free
              end

            bucket = %{bucket | free: free, leases: Map.delete(bucket.leases, lease_id)}
            {:reply, :ok, put_bucket(state, name, bucket)}
        end
    end
  end

  def handle_call({:active_leases, name}, _from, state) do
    now = state.clock.()

    count =
      case Map.fetch(state.buckets, name) do
        {:ok, bucket} ->
          Enum.count(bucket.leases, fn {_id, lease} -> lease.expires_at > now end)

        :error ->
          0
      end

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_info(:cleanup_tick, state) do
    state = run_cleanup(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info(:cleanup, state) do
    {:noreply, run_cleanup(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --------------------------------------------------------------------------
  # Internal helpers
  # --------------------------------------------------------------------------

  @spec new_bucket(number(), number(), integer()) :: map()
  defp new_bucket(capacity, refill_rate, now) do
    %{
      capacity: capacity,
      refill_rate: refill_rate,
      free: capacity * 1.0,
      last_refill: now,
      leases: %{}
    }
  end

  @spec touch(map(), integer()) :: map()
  defp touch(bucket, now) do
    bucket |> refill(now) |> expire(now)
  end

  @spec refill(map(), integer()) :: map()
  defp refill(%{last_refill: last} = bucket, now) when now > last do
    elapsed = now - last
    free = min(bucket.capacity, bucket.free + elapsed * bucket.refill_rate / 1000) * 1.0
    %{bucket | free: free, last_refill: now}
  end

  defp refill(bucket, _now), do: %{bucket | free: bucket.free * 1.0}

  @spec expire(map(), integer()) :: map()
  defp expire(bucket, now) do
    leases =
      bucket.leases
      |> Enum.reject(fn {_id, lease} -> lease.expires_at <= now end)
      |> Map.new()

    %{bucket | leases: leases}
  end

  @spec retry_after(map(), number()) :: non_neg_integer() | :infinity
  defp retry_after(bucket, tokens) do
    needed = tokens - bucket.free

    cond do
      tokens > bucket.capacity -> :infinity
      needed <= 0 -> 0
      bucket.refill_rate > 0 -> ceil(needed * 1000 / bucket.refill_rate)
      true -> :infinity
    end
  end

  @spec put_bucket(map(), bucket_name(), map()) :: map()
  defp put_bucket(state, name, bucket) do
    %{state | buckets: Map.put(state.buckets, name, bucket)}
  end

  @spec run_cleanup(map()) :: map()
  defp run_cleanup(state) do
    now = state.clock.()

    buckets =
      state.buckets
      |> Enum.map(fn {name, bucket} -> {name, touch(bucket, now)} end)
      |> Enum.reject(fn {_name, bucket} ->
        map_size(bucket.leases) == 0 and bucket.free >= bucket.capacity
      end)
      |> Map.new()

    %{state | buckets: buckets}
  end

  @spec schedule_cleanup(non_neg_integer() | :infinity) :: :ok | reference()
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) do
    Process.send_after(self(), :cleanup_tick, interval)
  end
end