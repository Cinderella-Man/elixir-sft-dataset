defmodule LeaseBucket do
  @moduledoc """
  A token-based leaky bucket where tokens are *reserved via leases* rather than
  consumed immediately.

  Callers reserve tokens with `acquire_lease/6` at the start of an operation and
  later settle the reservation with `release/4`:

    * `:completed` — the operation succeeded, so the tokens stay consumed.
    * `:cancelled` — the operation failed or was aborted, so the tokens are
      refunded to the bucket's free balance (capped at capacity).

  Leases that outlive their `lease_timeout_ms` are expired pessimistically and
  treated as `:completed` — tokens are never refunded automatically. Refunding
  expired leases would let a client reserve tokens indefinitely by simply never
  releasing them. Since the refill clock keeps advancing, the tokens consumed by
  an expired lease refill naturally over time, exactly like completed work.

  Refills are computed lazily on every operation that touches a bucket:

      new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)

  Buckets are created on first `acquire_lease/6` and are dropped by the periodic
  cleanup sweep once they have refilled to capacity and hold no active leases,
  because such a bucket is indistinguishable from a fresh one.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:cleanup_interval_ms` — interval between cleanup sweeps, or `:infinity` to
      disable the periodic timer entirely. Defaults to `60_000`.
    * `:name` — optional process registration name.
  """

  use GenServer

  @default_cleanup_interval_ms 60_000

  @typedoc "Opaque identifier for an outstanding lease."
  @type lease_id :: reference()

  @typedoc "How a lease was settled."
  @type outcome :: :completed | :cancelled

  @typedoc "Anything that can address the server process."
  @type server :: GenServer.server()

  defmodule Bucket do
    @moduledoc false

    defstruct [:capacity, :refill_rate, :tokens, :last_refill_at, leases: %{}]
  end

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the lease bucket server.

  Accepts `:clock`, `:cleanup_interval_ms` and `:name` options (see the module
  documentation). Any other options are ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Reserves `tokens` from `bucket_name` for up to `lease_timeout_ms` milliseconds.

  The bucket is created on first use with `capacity` tokens refilling at
  `refill_rate` tokens per second. Returns `{:ok, lease_id, remaining}` where
  `remaining` is the floor of the free balance after the reservation, or
  `{:error, :empty, retry_after_ms}` when the bucket lacks enough free tokens.

  Raises `FunctionClauseError` for out-of-contract arguments: `capacity`,
  `tokens` and `lease_timeout_ms` must be positive integers, `refill_rate` must
  be a positive number, and `tokens` must not exceed `capacity`.
  """
  @spec acquire_lease(server(), term(), pos_integer(), number(), pos_integer(), pos_integer()) ::
          {:ok, lease_id(), non_neg_integer()} | {:error, :empty, non_neg_integer()}
  def acquire_lease(server, bucket_name, capacity, refill_rate, tokens, lease_timeout_ms)
      when is_integer(capacity) and capacity > 0 and
             is_number(refill_rate) and refill_rate > 0 and
             is_integer(tokens) and tokens > 0 and tokens <= capacity and
             is_integer(lease_timeout_ms) and lease_timeout_ms > 0 do
    GenServer.call(
      server,
      {:acquire_lease, bucket_name, capacity, refill_rate, tokens, lease_timeout_ms}
    )
  end

  @doc """
  Settles the lease `lease_id` held against `bucket_name`.

  With `:completed` the reserved tokens stay consumed; with `:cancelled` they are
  refunded to the bucket's free balance (capped at capacity). Returns `:ok`, or
  `{:error, :unknown_lease}` if the lease is unknown — already released, expired,
  or never issued — in which case no state is mutated.
  """
  @spec release(server(), term(), lease_id(), outcome()) :: :ok | {:error, :unknown_lease}
  def release(server, bucket_name, lease_id, outcome)
      when is_reference(lease_id) and outcome in [:completed, :cancelled] do
    GenServer.call(server, {:release, bucket_name, lease_id, outcome})
  end

  @doc """
  Returns `{:ok, count}` with the number of outstanding leases for `bucket_name`.

  Leases past their expiry are swept before counting, and unknown buckets report
  `{:ok, 0}`.
  """
  @spec active_leases(server(), term()) :: {:ok, non_neg_integer()}
  def active_leases(server, bucket_name) do
    GenServer.call(server, {:active_leases, bucket_name})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      buckets: %{},
      clock: clock,
      cleanup_interval_ms: interval
    }

    schedule_cleanup(interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(
        {:acquire_lease, name, capacity, refill_rate, tokens, lease_timeout_ms},
        _from,
        state
      ) do
    now = state.clock.()

    bucket =
      state.buckets
      |> Map.get(name)
      |> init_bucket(capacity, refill_rate, now)
      |> refill(now)
      |> expire_leases(now)

    if bucket.tokens >= tokens do
      lease_id = make_ref()

      bucket = %Bucket{
        bucket
        | tokens: bucket.tokens - tokens,
          leases: Map.put(bucket.leases, lease_id, {tokens, now + lease_timeout_ms})
      }

      remaining = floor(bucket.tokens)
      {:reply, {:ok, lease_id, remaining}, put_bucket(state, name, bucket)}
    else
      retry_after_ms = retry_after_ms(bucket, tokens)
      {:reply, {:error, :empty, retry_after_ms}, put_bucket(state, name, bucket)}
    end
  end

  def handle_call({:release, name, lease_id, outcome}, _from, state) do
    case Map.fetch(state.buckets, name) do
      :error ->
        {:reply, {:error, :unknown_lease}, state}

      {:ok, bucket} ->
        now = state.clock.()

        bucket =
          bucket
          |> refill(now)
          |> expire_leases(now)

        case Map.pop(bucket.leases, lease_id) do
          {nil, _leases} ->
            {:reply, {:error, :unknown_lease}, put_bucket(state, name, bucket)}

          {{tokens, _expires_at}, leases} ->
            tokens_after =
              case outcome do
                :completed -> bucket.tokens
                :cancelled -> min(bucket.capacity * 1.0, bucket.tokens + tokens)
              end

            bucket = %Bucket{bucket | tokens: tokens_after, leases: leases}
            {:reply, :ok, put_bucket(state, name, bucket)}
        end
    end
  end

  def handle_call({:active_leases, name}, _from, state) do
    case Map.fetch(state.buckets, name) do
      :error ->
        {:reply, {:ok, 0}, state}

      {:ok, bucket} ->
        now = state.clock.()

        bucket =
          bucket
          |> refill(now)
          |> expire_leases(now)

        {:reply, {:ok, map_size(bucket.leases)}, put_bucket(state, name, bucket)}
    end
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    buckets =
      state.buckets
      |> Enum.reduce(%{}, fn {name, bucket}, acc ->
        bucket =
          bucket
          |> refill(now)
          |> expire_leases(now)

        if collectable?(bucket), do: acc, else: Map.put(acc, name, bucket)
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | buckets: buckets}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ── Internals ─────────────────────────────────────────────────────────────

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  defp init_bucket(nil, capacity, refill_rate, now) do
    %Bucket{
      capacity: capacity,
      refill_rate: refill_rate,
      tokens: capacity * 1.0,
      last_refill_at: now,
      leases: %{}
    }
  end

  defp init_bucket(%Bucket{} = bucket, _capacity, _refill_rate, _now), do: bucket

  defp refill(%Bucket{} = bucket, now) do
    elapsed = max(now - bucket.last_refill_at, 0)
    tokens = min(bucket.capacity * 1.0, bucket.tokens + elapsed * bucket.refill_rate / 1000)
    %Bucket{bucket | tokens: tokens, last_refill_at: now}
  end

  # Expired leases are pessimistically treated as completed: the tracking entry
  # is dropped and the reserved tokens stay consumed (they refill over time).
  defp expire_leases(%Bucket{} = bucket, now) do
    leases =
      Map.reject(bucket.leases, fn {_lease_id, {_tokens, expires_at}} -> expires_at <= now end)

    %Bucket{bucket | leases: leases}
  end

  defp put_bucket(state, name, bucket), do: %{state | buckets: Map.put(state.buckets, name, bucket)}

  defp collectable?(%Bucket{} = bucket) do
    map_size(bucket.leases) == 0 and bucket.tokens >= bucket.capacity
  end

  defp retry_after_ms(%Bucket{} = bucket, tokens) do
    deficit = tokens - bucket.tokens

    if deficit <= +0.0 do
      0
    else
      ceil(deficit * 1000 / bucket.refill_rate)
    end
  end
end