Implement the `handle_info/2` clause that handles the `:cleanup` message.

Get the current time by calling `state.clock.()`.

Build a new bucket map that drops any entry whose `last_access` is older than `state.cleanup_ttl_ms` milliseconds ago (i.e. where `now - bucket.last_access` exceeds `state.cleanup_ttl_ms`) and keeps all other entries unchanged.

Reschedule the next cleanup sweep using the private `schedule_cleanup/1` helper with `state.cleanup_interval_ms`.

Return `{:noreply, new_state}` where `new_state` is `state` with its `buckets` field replaced by the filtered map.

```elixir
defmodule LeakyBucket do
  @moduledoc """
  A token-based leaky bucket rate limiter implemented as a GenServer.

  Tokens are refilled lazily on each `acquire/5` call based on elapsed time,
  rather than via per-bucket timers. A periodic cleanup sweep removes buckets
  that haven't been accessed within a configurable TTL to prevent memory leaks.
  """

  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────

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

  # ── GenServer callbacks ────────────────────────────────────────────────

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
  def handle_call({:acquire, bucket_name, capacity, refill_rate, tokens}, _from, %State{} = state) do
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
    # TODO
  end

  # Catch-all so unexpected messages don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private helpers ────────────────────────────────────────────────────

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