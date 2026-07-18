# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule LeaseBucket do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

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

  def release(server, bucket, lease_id, outcome) when outcome in [:completed, :cancelled] do
    GenServer.call(server, {:release, bucket, lease_id, outcome})
  end

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
