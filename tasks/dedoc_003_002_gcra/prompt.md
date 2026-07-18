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
defmodule GcraLimiter do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  def acquire(server, bucket_name, rate_per_sec, burst_size, tokens \\ 1)
      when is_number(rate_per_sec) and rate_per_sec > 0 and
             is_integer(burst_size) and burst_size > 0 and
             is_integer(tokens) and tokens > 0 do
    GenServer.call(server, {:acquire, bucket_name, rate_per_sec, burst_size, tokens})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000
  @default_cleanup_idle_ms 300_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    cleanup_idle = Keyword.get(opts, :cleanup_idle_ms, @default_cleanup_idle_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{bucket_name => tat_ms (float)}
       buckets: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval,
       cleanup_idle_ms: cleanup_idle
     }}
  end

  @impl true
  def handle_call({:acquire, bucket, rate_per_sec, burst, tokens}, _from, state) do
    now = state.clock.()

    # Derived constants.
    emission_interval = 1000 / rate_per_sec
    dvt = burst * emission_interval

    # Fresh bucket starts at TAT = now (full burst immediately available).
    tat = Map.get(state.buckets, bucket, now * 1.0)

    # Advance the TAT baseline if the bucket has been idle past it —
    # without this `max`, idle time would be credited beyond `burst`.
    new_tat = max(now, tat) + tokens * emission_interval
    earliest_admit = new_tat - dvt

    if earliest_admit <= now do
      # Accept.  The remaining burst headroom, expressed in tokens, is how
      # much slack we still have between (new_tat - now) and DVT.
      slack = dvt - (new_tat - now)
      remaining = max(trunc(slack / emission_interval), 0)

      {:reply, {:ok, remaining}, %{state | buckets: Map.put(state.buckets, bucket, new_tat)}}
    else
      # Reject.  Crucially, do NOT update TAT — repeated rejects must not
      # push the admit frontier further into the future.
      retry_after = ceil_positive(earliest_admit - now)
      {:reply, {:error, :rate_exceeded, retry_after}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()
    idle_threshold = state.cleanup_idle_ms

    cleaned =
      Enum.reduce(state.buckets, %{}, fn {bucket, tat}, acc ->
        # If TAT is far enough in the past that the bucket would behave
        # identically to a fresh one, drop it.
        if now - tat >= idle_threshold do
          acc
        else
          Map.put(acc, bucket, tat)
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | buckets: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Ceiling that always returns a positive integer, suitable for retry_after.
  defp ceil_positive(x) do
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
