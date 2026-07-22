defmodule SharedPoolBucket do
  @moduledoc """
  A two-level token-bucket rate limiter.

  Every named bucket (a tenant, an API key, a user) has its own capacity and
  refill rate, and *in addition* every acquire draws against a single global
  pool that is shared by all buckets and constrains the whole server.

  A request succeeds only when **both** levels have enough tokens:

    * the per-key bucket, whose capacity/refill rate are supplied per acquire
      (the bucket is created full, lazily, the first time it is seen), and
    * the global pool, configured once at `start_link/1` and started full.

  If either level is short, **nothing is drained from either level**. When both
  levels are short the per-key error wins: a caller whose own tier is depleted
  should not be told that the global pool is their blocker.

  Both levels use the standard lazy-refill formula, applied before the drain is
  evaluated:

      new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)

  Time comes from an injectable zero-arity clock (`:clock`), so tests can drive
  the limiter deterministically without sleeping.

  ## Example

      {:ok, pid} =
        SharedPoolBucket.start_link(global_capacity: 10, global_refill_rate: 5.0)

      {:ok, 4, 9} = SharedPoolBucket.acquire(pid, "tenant_a", 5, 1.0, 1)
      {:ok, 9} = SharedPoolBucket.global_level(pid)
      {:ok, 4} = SharedPoolBucket.key_level(pid, "tenant_a", 5, 1.0)

  ## Cleanup

  Every `:cleanup_interval_ms` milliseconds (default `60_000`, or `:infinity` to
  disable the timer entirely) the server drops each per-key bucket whose
  projected balance has refilled back to its capacity — such a bucket is
  indistinguishable from a fresh one, so forgetting it is free. The global pool
  is never dropped. Sending the process a bare `:cleanup` message runs one such
  pass immediately.
  """

  use GenServer

  @default_cleanup_interval_ms 60_000

  @typedoc "Name of a per-key bucket. Any term may be used."
  @type bucket_name :: term()

  @typedoc "Server reference accepted by the public API."
  @type server :: GenServer.server()

  @typedoc "Zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  defmodule Bucket do
    @moduledoc false
    # Per-key bucket state: current tokens (float), last access timestamp, and
    # the last-known capacity / refill rate (they are supplied per acquire).
    @enforce_keys [:tokens, :last_ms, :capacity, :refill_rate]
    defstruct [:tokens, :last_ms, :capacity, :refill_rate]
  end

  defmodule State do
    @moduledoc false
    # Top-level state. The global pool lives here, NOT in the buckets map.
    @enforce_keys [
      :buckets,
      :global_tokens,
      :global_last_ms,
      :global_capacity,
      :global_refill_rate,
      :clock,
      :cleanup_interval_ms
    ]
    defstruct [
      :buckets,
      :global_tokens,
      :global_last_ms,
      :global_capacity,
      :global_refill_rate,
      :clock,
      :cleanup_interval_ms
    ]
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the rate limiter.

  ## Options

    * `:global_capacity` — maximum number of tokens in the shared pool
      (required, positive integer). The pool starts full.
    * `:global_refill_rate` — pool refill rate in tokens per second (required,
      positive number).
    * `:clock` — zero-arity function returning the current time in milliseconds
      (default `fn -> System.monotonic_time(:millisecond) end`).
    * `:cleanup_interval_ms` — periodic sweep interval in milliseconds
      (default `60_000`). Use `:infinity` to disable the periodic sweep.
    * `:name` — optional name to register the process under.

  Any other option is passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Attempts to drain `tokens` from the named bucket **and** the global pool.

  Both levels are lazily refilled first, then the drain is evaluated
  atomically: if either level is short, nothing is drained anywhere.

  Returns:

    * `{:ok, key_remaining, global_remaining}` — both integer floors of the
      post-drain balances;
    * `{:error, :key_empty, retry_after_ms}` — the per-key bucket is short
      (this takes precedence when both levels are short);
    * `{:error, :global_empty, retry_after_ms}` — the per-key bucket would have
      admitted the request but the global pool is short.

  `retry_after_ms` is rounded up from `deficit * 1000 / refill_rate` and is
  always at least `1`.

  Raises `FunctionClauseError` for a non-positive `key_capacity`,
  `key_refill_rate` or `tokens`; such a call never drains tokens and never
  creates a bucket.
  """
  @spec acquire(server(), bucket_name(), pos_integer(), number(), pos_integer()) ::
          {:ok, non_neg_integer(), non_neg_integer()}
          | {:error, :key_empty | :global_empty, pos_integer()}
  def acquire(server, bucket_name, key_capacity, key_refill_rate, tokens \\ 1)
      when is_integer(key_capacity) and key_capacity > 0 and
             is_number(key_refill_rate) and key_refill_rate > 0 and
             is_integer(tokens) and tokens > 0 do
    GenServer.call(
      server,
      {:acquire, bucket_name, key_capacity, key_refill_rate, tokens}
    )
  end

  @doc """
  Returns `{:ok, remaining}` — the floor of the global pool balance after the
  lazy refill has been applied. Does not drain anything.
  """
  @spec global_level(server()) :: {:ok, non_neg_integer()}
  def global_level(server) do
    GenServer.call(server, :global_level)
  end

  @doc """
  Returns `{:ok, remaining}` — the floor of the named bucket's balance after the
  lazy refill has been applied, or `{:ok, key_capacity}` if the bucket has never
  been seen. Does not drain anything and does not create the bucket.

  The capacity and refill rate must be supplied because buckets are defined per
  acquire rather than at creation time.

  Raises `FunctionClauseError` for a non-positive `key_capacity` or
  `key_refill_rate`.
  """
  @spec key_level(server(), bucket_name(), pos_integer(), number()) ::
          {:ok, non_neg_integer()}
  def key_level(server, bucket_name, key_capacity, key_refill_rate)
      when is_integer(key_capacity) and key_capacity > 0 and
             is_number(key_refill_rate) and key_refill_rate > 0 do
    GenServer.call(server, {:key_level, bucket_name, key_capacity, key_refill_rate})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    global_capacity = fetch_global_capacity!(opts)
    global_refill_rate = fetch_global_refill_rate!(opts)
    clock = fetch_clock!(opts)
    cleanup_interval_ms = fetch_cleanup_interval!(opts)

    state = %State{
      buckets: %{},
      global_tokens: global_capacity * 1.0,
      global_last_ms: clock.(),
      global_capacity: global_capacity,
      global_refill_rate: global_refill_rate,
      clock: clock,
      cleanup_interval_ms: cleanup_interval_ms
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:acquire, name, key_capacity, key_refill_rate, tokens}, _from, state) do
    now = state.clock.()

    bucket =
      state.buckets
      |> fetch_bucket(name, key_capacity, key_refill_rate, now)
      |> refill_bucket(key_capacity, key_refill_rate, now)

    global_tokens =
      refill(
        state.global_tokens,
        state.global_last_ms,
        state.global_capacity,
        state.global_refill_rate,
        now
      )

    key_ok? = bucket.tokens >= tokens
    global_ok? = global_tokens >= tokens

    # Refills are always persisted; drains only happen when both levels admit.
    state = %State{state | global_tokens: global_tokens, global_last_ms: now}

    cond do
      not key_ok? ->
        state = put_bucket(state, name, bucket)
        retry = retry_after_ms(tokens - bucket.tokens, key_refill_rate)
        {:reply, {:error, :key_empty, retry}, state}

      not global_ok? ->
        state = put_bucket(state, name, bucket)
        retry = retry_after_ms(tokens - global_tokens, state.global_refill_rate)
        {:reply, {:error, :global_empty, retry}, state}

      true ->
        drained = %Bucket{bucket | tokens: bucket.tokens - tokens}

        state =
          state
          |> put_bucket(name, drained)
          |> Map.put(:global_tokens, global_tokens - tokens)

        {:reply, {:ok, floor_tokens(drained.tokens), floor_tokens(state.global_tokens)}, state}
    end
  end

  def handle_call(:global_level, _from, state) do
    now = state.clock.()

    global_tokens =
      refill(
        state.global_tokens,
        state.global_last_ms,
        state.global_capacity,
        state.global_refill_rate,
        now
      )

    state = %State{state | global_tokens: global_tokens, global_last_ms: now}
    {:reply, {:ok, floor_tokens(global_tokens)}, state}
  end

  def handle_call({:key_level, name, key_capacity, key_refill_rate}, _from, state) do
    now = state.clock.()

    case Map.fetch(state.buckets, name) do
      :error ->
        # Never seen: a fresh bucket would be full.
        {:reply, {:ok, key_capacity}, state}

      {:ok, bucket} ->
        bucket = refill_bucket(bucket, key_capacity, key_refill_rate, now)
        {:reply, {:ok, floor_tokens(bucket.tokens)}, put_bucket(state, name, bucket)}
    end
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    state = sweep(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Option parsing
  # ---------------------------------------------------------------------------

  defp fetch_global_capacity!(opts) do
    case Keyword.fetch(opts, :global_capacity) do
      {:ok, capacity} when is_integer(capacity) and capacity > 0 ->
        capacity

      {:ok, other} ->
        raise ArgumentError,
              ":global_capacity must be a positive integer, got: #{inspect(other)}"

      :error ->
        raise ArgumentError, ":global_capacity is required"
    end
  end

  defp fetch_global_refill_rate!(opts) do
    case Keyword.fetch(opts, :global_refill_rate) do
      {:ok, rate} when is_number(rate) and rate > 0 ->
        rate

      {:ok, other} ->
        raise ArgumentError,
              ":global_refill_rate must be a positive number, got: #{inspect(other)}"

      :error ->
        raise ArgumentError, ":global_refill_rate is required"
    end
  end

  defp fetch_clock!(opts) do
    case Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end) do
      clock when is_function(clock, 0) ->
        clock

      other ->
        raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(other)}"
    end
  end

  defp fetch_cleanup_interval!(opts) do
    case Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms) do
      :infinity ->
        :infinity

      interval when is_integer(interval) and interval > 0 ->
        interval

      other ->
        raise ArgumentError,
              ":cleanup_interval_ms must be a positive integer or :infinity, " <>
                "got: #{inspect(other)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Token math
  # ---------------------------------------------------------------------------

  defp fetch_bucket(buckets, name, key_capacity, key_refill_rate, now) do
    case Map.fetch(buckets, name) do
      {:ok, bucket} ->
        bucket

      :error ->
        %Bucket{
          tokens: key_capacity * 1.0,
          last_ms: now,
          capacity: key_capacity,
          refill_rate: key_refill_rate
        }
    end
  end

  defp refill_bucket(%Bucket{} = bucket, capacity, refill_rate, now) do
    tokens = refill(bucket.tokens, bucket.last_ms, capacity, refill_rate, now)

    %Bucket{
      bucket
      | tokens: tokens,
        last_ms: now,
        capacity: capacity,
        refill_rate: refill_rate
    }
  end

  # new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)
  defp refill(tokens, last_ms, capacity, refill_rate, now) do
    elapsed_ms = max(now - last_ms, 0)
    min(capacity * 1.0, tokens + elapsed_ms * refill_rate / 1000)
  end

  # A shortage always reports at least 1 ms, rounded up from the exact
  # deficit * 1000 / refill_rate computation.
  defp retry_after_ms(deficit, refill_rate) when deficit > 0 do
    max(ceil(deficit * 1000 / refill_rate), 1)
  end

  defp retry_after_ms(_deficit, _refill_rate), do: 1

  defp floor_tokens(tokens) when is_float(tokens), do: max(floor(tokens), 0)

  defp put_bucket(%State{} = state, name, %Bucket{} = bucket) do
    %State{state | buckets: Map.put(state.buckets, name, bucket)}
  end

  # ---------------------------------------------------------------------------
  # Cleanup
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(%State{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%State{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  # Drop every per-key bucket whose projected balance has refilled back to its
  # capacity — it is indistinguishable from a fresh bucket. The global pool is
  # never dropped.
  defp sweep(%State{} = state) do
    now = state.clock.()

    buckets =
      Enum.reject(state.buckets, fn {_name, bucket} ->
        refill(bucket.tokens, bucket.last_ms, bucket.capacity, bucket.refill_rate, now) >=
          bucket.capacity * 1.0
      end)
      |> Map.new()

    %State{state | buckets: buckets}
  end
end