defmodule HierarchicalLimiter do
  @moduledoc """
  A GenServer that enforces multiple simultaneous sliding-window rate limits
  per key.  A request is accepted only when it passes every configured tier.

  Each key is backed by a single sorted list of request timestamps (newest
  first).  For each incoming `check/3` call, every tier counts how many
  recorded timestamps fall within its own window.  If any tier's count has
  already reached its limit, the request is rejected and the tightest
  offending tier is reported — "tightest" meaning the tier whose oldest
  in-window timestamp is farthest from expiring (longest retry_after).

  Rejected requests do **not** record a new timestamp, so they don't consume
  budget under any tier.

  Timestamps older than the widest tier window are dropped lazily on every
  check and aggressively during the periodic cleanup sweep, bounding the
  per-key state.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = HierarchicalLimiter.start_link([])
      iex> tiers = [{:per_second, 10, 1_000}, {:per_minute, 100, 60_000}]
      iex> {:ok, %{per_second: 9, per_minute: 99}} = HierarchicalLimiter.check(pid, "user:1", tiers)

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

  @doc """
  Checks whether a request for `key` passes every tier in `tiers`.

  `tiers` is a list of `{tier_name, max_requests, window_ms}` tuples.  A
  request is accepted only when every tier has capacity.  On success, returns
  `{:ok, remaining_by_tier}` — a map from tier name to the remaining
  allowance under that tier after accepting the request.

  On failure, returns `{:error, :rate_limited, tier_name, retry_after_ms}`
  identifying the tier that kept the request out for the longest and the wait
  (in milliseconds) until that tier's oldest in-window timestamp expires.
  """
  @spec check(GenServer.server(), term(), [{atom(), pos_integer(), pos_integer()}, ...]) ::
          {:ok, %{atom() => non_neg_integer()}}
          | {:error, :rate_limited, atom(), non_neg_integer()}
  def check(server, key, [_ | _] = tiers) do
    :ok = validate_tiers!(tiers)
    GenServer.call(server, {:check, key, tiers})
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

    # Fetch and lazily prune to the widest tier window.
    {timestamps, _old_widest} = Map.get(state.keys, key, {[], widest_window})
    active = Enum.take_while(timestamps, fn ts -> ts > now - widest_window end)

    # Evaluate every tier against the pruned list.
    case evaluate_tiers(tiers, active, now) do
      {:ok, remaining_by_tier} ->
        # All tiers pass — record this request's timestamp at the front.
        new_entry = {[now | active], widest_window}
        {:reply, {:ok, remaining_by_tier}, %{state | keys: Map.put(state.keys, key, new_entry)}}

      {:rejected, tier_name, retry_after} ->
        # Persist the pruned list even on failure so we don't re-prune next time.
        new_entry = {active, widest_window}

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
          # Tier saturated.  The oldest in-window timestamp is the last one
          # in the truncated list (timestamps are newest-first).  Wait until
          # it exits the window.
          oldest = List.last(in_window)
          retry_after = max(oldest + window_ms - now, 1)
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
