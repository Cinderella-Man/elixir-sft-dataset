# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `check` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Hey — I need you to write me an Elixir GenServer module called `HierarchicalLimiter` that enforces **multiple simultaneous** rate limits per key using a sliding window algorithm. Here's the motivation so it makes sense: real APIs often advertise tiered limits like "10 requests/second AND 100 requests/minute AND 1000 requests/hour", and a request is only allowed if it passes **every** tier. This module needs to enforce all tiers against the same stream of request timestamps.

For the public API, I need these functions. First, `HierarchicalLimiter.start_link(opts)` to start the process — it should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds, and if that's not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

Then `HierarchicalLimiter.check(server, key, tiers)`, where `tiers` is a non-empty list of `{tier_name, max_requests, window_ms}` tuples — for example `[{:per_second, 10, 1_000}, {:per_minute, 100, 60_000}, {:per_hour, 1000, 3_600_000}]`. The tier_name is an atom used for reporting which tier was exceeded. If the request passes every tier, return `{:ok, remaining_by_tier}` where `remaining_by_tier` is a map like `%{per_second: 7, per_minute: 94, per_hour: 893}` — the remaining allowance under each tier after accepting this request. If any tier would be exceeded, return `{:error, :rate_limited, tier_name, retry_after_ms}` identifying the tightest tier that rejected the request and how long until that specific tier would admit a new request (i.e. long enough for enough of its oldest in-window timestamps to expire that the tier drops below its limit — which, when the tier is over by more than one, is longer than waiting for just the single oldest entry to expire). By "tightest" I mean the tier with the longest retry_after (i.e. the tier the caller needs to wait on). And do not record the timestamp when the request is rejected — a rejected request should not consume budget under any tier.

Each key must be tracked independently. Internally, keep a single list of timestamps per key (shared across tiers) and evaluate each tier against that list by counting entries within the tier's window. The widest tier's window determines how long timestamps must be retained; timestamps older than that window can be discarded. Remember the widest window ever seen for a key across all of its checks, so that a later check using only narrower tiers does not shrink how far back timestamps are retained — a check's own timestamps, and those recorded by earlier wide-tier checks, must remain available to a subsequent wide-tier check.

I also want to make sure expired entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that prunes timestamps older than the widest window seen for each key, and drops keys whose timestamp list becomes empty.

Give me the complete module in a single file, and use only OTP standard library — no external dependencies.

A couple more things on the interface contract. The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically. And sending the server process a bare `:cleanup` message should perform one cleanup pass immediately — the same work the periodic timer performs.

## The module with `check` missing

```elixir
defmodule HierarchicalLimiter do
  @moduledoc """
  A GenServer that enforces multiple simultaneous sliding-window rate limits
  per key.  A request is accepted only when it passes every configured tier.

  Each key is backed by a single sorted list of request timestamps (newest
  first).  For each incoming `check/3` call, every tier counts how many
  recorded timestamps fall within its own window.  If any tier's count has
  already reached its limit, the request is rejected and the tightest
  offending tier is reported — "tightest" meaning the tier the caller must
  wait longest on (longest retry_after).

  A tier's retry_after is the time until enough of its oldest in-window
  timestamps expire that the tier would admit a new request.  When a tier is
  over its limit by more than one entry, that means waiting for several of the
  oldest entries to leave the window — not merely the single oldest.

  Rejected requests do **not** record a new timestamp, so they don't consume
  budget under any tier.

  Timestamps older than the widest tier window ever seen for a key are dropped
  lazily on every check and aggressively during the periodic cleanup sweep,
  bounding the per-key state.  The widest window is remembered across checks so
  that a later narrow check cannot cause a wide tier's history to be discarded.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = HierarchicalLimiter.start_link([])
      iex> tiers = [{:per_second, 10, 1_000}, {:per_minute, 100, 60_000}]
      iex> {:ok, %{per_second: 9, per_minute: 99}} =
      ...>   HierarchicalLimiter.check(pid, "user:1", tiers)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the HierarchicalLimiter process and links it to the caller.

  ## Options

    * `:name`                 – optional registered name
    * `:clock`                – `(-> integer())` returning now in milliseconds
    * `:cleanup_interval_ms`  – sweep interval (default `60_000`)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  def check(server, key, [_ | _] = tiers) do
    # TODO
  end

  defp validate_tiers!(tiers) do
    Enum.each(tiers, fn
      {name, max, window}
      when is_atom(name) and is_integer(max) and max > 0 and
             is_integer(window) and window > 0 ->
        :ok

      bad ->
        raise ArgumentError,
              "invalid tier #{inspect(bad)} — expected {atom, pos_integer, pos_integer}"
    end)

    :ok
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
       # %{key => {[timestamp_newest_first], widest_window_seen_ms}}
       keys: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, tiers}, _from, state) do
    now = state.clock.()
    widest_window = tiers |> Enum.map(fn {_n, _m, w} -> w end) |> Enum.max()

    # Fetch and lazily prune to the widest window ever seen for this key so a
    # narrow check can't discard timestamps a wider tier still needs.
    {timestamps, old_widest} = Map.get(state.keys, key, {[], 0})
    widest = max(old_widest, widest_window)
    active = Enum.take_while(timestamps, fn ts -> ts > now - widest end)

    # Evaluate every tier against the pruned list.
    case evaluate_tiers(tiers, active, now) do
      {:ok, remaining_by_tier} ->
        # All tiers pass — record this request's timestamp at the front.
        new_entry = {[now | active], widest}
        {:reply, {:ok, remaining_by_tier}, %{state | keys: Map.put(state.keys, key, new_entry)}}

      {:rejected, tier_name, retry_after} ->
        # Persist the pruned list even on failure so we don't re-prune next time.
        new_entry = {active, widest}

        {:reply, {:error, :rate_limited, tier_name, retry_after},
         %{state | keys: Map.put(state.keys, key, new_entry)}}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      Enum.reduce(state.keys, %{}, fn {key, {timestamps, widest}}, acc ->
        cutoff = now - widest
        active = Enum.take_while(timestamps, fn ts -> ts > cutoff end)

        if active == [] do
          acc
        else
          Map.put(acc, key, {active, widest})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
  end

  # Catch-all so unexpected messages don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Tier evaluation
  # ---------------------------------------------------------------------------

  # For each tier: count the in-window timestamps.  If any tier is at its
  # limit, collect its retry_after and pick the tightest (longest wait).
  # Otherwise, build the remaining_by_tier map.
  defp evaluate_tiers(tiers, active, now) do
    results =
      Enum.map(tiers, fn {name, max_requests, window_ms} ->
        window_start = now - window_ms
        in_window = Enum.take_while(active, fn ts -> ts > window_start end)
        count = length(in_window)

        if count < max_requests do
          # `count` already-recorded requests; after accepting the new one,
          # `count + 1` will exist, leaving `max_requests - count - 1` headroom.
          {:pass, name, max_requests - count - 1}
        else
          # Tier saturated.  To admit a new request the in-window count must
          # drop to `max_requests - 1`, so the `count - max_requests + 1`
          # oldest timestamps must leave the window.  Wait until the newest of
          # those (the k-th oldest) expires.  When over by exactly one, k = 1,
          # i.e. just the single oldest entry.
          k = count - max_requests + 1
          nth_oldest = in_window |> Enum.reverse() |> Enum.at(k - 1)
          retry_after = max(nth_oldest + window_ms - now, 1)
          {:fail, name, retry_after}
        end
      end)

    case Enum.filter(results, &match?({:fail, _, _}, &1)) do
      [] ->
        remaining =
          Enum.reduce(results, %{}, fn {:pass, name, r}, acc -> Map.put(acc, name, r) end)

        {:ok, remaining}

      failures ->
        # Tightest = longest retry_after (the one the caller actually has to wait on).
        {:fail, name, retry_after} =
          Enum.max_by(failures, fn {:fail, _n, retry} -> retry end)

        {:rejected, name, retry_after}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```

Reply with `check` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
