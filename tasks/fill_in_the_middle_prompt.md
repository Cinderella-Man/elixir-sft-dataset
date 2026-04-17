So I have this module which is designed to be single-shot SFT answer.
I would like to now to create "fill-in-the-middle" tasks out of it.
I would like to create two tasks for:
- `handle_call({:acquire, bucket_name, capacity, refill_rate, tokens}, _from, %State{} = state)`
- `handle_info(:cleanup, %State{} = state)`

Can you generate two prompts that could be given as tasks to implement those functions (one at the time).

Here's an example of prompt for similar task:

```
Implement the private `handle_closed/2` function. It should execute the provided zero-arity function using `execute/1`.

If the execution succeeds, reset `failure_count` to 0 and return the result in the GenServer reply.

If the execution fails, increment `failure_count`. If the updated count is greater than or equal to `failure_threshold`, transition the circuit to the `:open` state using `trip_open/1`.

In all cases, return the result produced by `execute/1` in the GenServer reply along with the updated state.
```

This will be given together with the whole module with the function's body erased (just # TODO inside instead)

Here's the whole module:

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

And here's the original prompt that generated the whole module:

```
Write me an Elixir GenServer module called `LeakyBucket` that implements a token-based leaky bucket algorithm for traffic shaping.

I need these functions in the public API:

- `LeakyBucket.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `LeakyBucket.acquire(server, bucket_name, capacity, refill_rate, tokens \\ 1)` which attempts to drain `tokens` from the named bucket. `capacity` is the maximum number of tokens the bucket can hold, and `refill_rate` is the number of tokens added per second. If enough tokens are available, drain them and return `{:ok, remaining}` where `remaining` is how many tokens are left after the drain. If not enough tokens are available, return `{:error, :empty, retry_after_ms}` where `retry_after_ms` is how many milliseconds the caller should wait before enough tokens have refilled to satisfy the request.

Each bucket name must be tracked independently — draining "api:uploads" should have no effect on "api:downloads". A brand new bucket that has never been seen before should start full at `capacity` tokens.

Token refill must be calculated lazily on each `acquire` call based on elapsed time since the last access, not via a timer per bucket. The formula is: `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. This means if a bucket has 0 tokens, a capacity of 10, and a refill rate of 5 tokens/second, then after 1000ms it should have 5 tokens, and after 2000ms it should be full at 10 (never exceeding capacity).

You also need to make sure stale bucket entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes tracking data for any bucket that hasn't been accessed within the last `cleanup_ttl_ms` milliseconds (default 300_000, i.e. 5 minutes). The cleanup should be based on the injectable clock, not wall time.

Store the GenServer state as a struct or map with a `buckets` key that holds a map of bucket_name => bucket_data. Each bucket_data should track at least the current token count (as a float for fractional refills), the last access timestamp, and whatever else you need.

The `remaining` value returned on success should be an integer (floor of the float token count after draining).

The `retry_after_ms` value returned on rejection should be a positive integer representing the ceiling of the time needed to refill enough tokens.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
```