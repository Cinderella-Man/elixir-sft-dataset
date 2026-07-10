Implement the `handle_call/3` callback for the `{:check, ...}` message. 

First, fetch the current time using the clock in the state and retrieve the tracking data for the `key` (use `empty_entry/0` if the key is new). Apply the strike decay logic to the entry before proceeding.

If a cooldown period was previously active but the current time has passed the `cooldown_end`, clear the cooldown. If the cooldown is still active, return a GenServer reply with `{:error, :cooling_down, retry_after_ms, strike_count}`.

If no cooldown is active, delegate to `evaluate_window/7` to determine if the request should be permitted.

```elixir
defmodule PenaltyLimiter do
  @moduledoc """
  A GenServer that enforces per-key rate limits with escalating cooldowns for
  repeat offenders.
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

  @spec check(GenServer.server(), term(), pos_integer(), pos_integer(), [pos_integer(), ...]) ::
          {:ok, non_neg_integer()}
          | {:error, :rate_limited, non_neg_integer(), pos_integer()}
          | {:error, :cooling_down, non_neg_integer(), pos_integer()}
  def check(server, key, max_requests, window_ms, [_ | _] = penalty_ladder)
      when is_integer(max_requests) and max_requests > 0 and
             is_integer(window_ms) and window_ms > 0 do
    Enum.each(penalty_ladder, fn
      d when is_integer(d) and d > 0 ->
        :ok

      bad ->
        raise ArgumentError,
              "penalty ladder entries must be positive integers, got #{inspect(bad)}"
    end)

    GenServer.call(server, {:check, key, max_requests, window_ms, penalty_ladder})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  defp empty_entry do
    %{timestamps: [], strikes: 0, last_strike_at: nil, cooldown_end: nil, window_ms: nil}
  end

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       keys: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms, ladder}, _from, state) do
    # TODO
  end

  defp evaluate_window(state, key, entry, now, max_requests, window_ms, ladder) do
    window_start = now - window_ms

    # Timestamps are stored newest-first, so the scan stops at the first
    # expired entry.
    active = Enum.take_while(entry.timestamps, fn ts -> ts > window_start end)
    count = length(active)

    if count < max_requests do
      new_entry = %{entry | timestamps: [now | active], cooldown_end: nil, window_ms: window_ms}
      remaining = max_requests - count - 1

      {:reply, {:ok, remaining}, %{state | keys: Map.put(state.keys, key, new_entry)}}
    else
      new_strikes = entry.strikes + 1
      cooldown_ms = ladder_value(ladder, new_strikes)

      # Newest-first order makes the last active entry the oldest one.
      oldest = List.last(active)
      window_retry = oldest + window_ms - now

      # retry_after covers both the window expiry and the new strike's cooldown.
      retry_after = max(max(window_retry, cooldown_ms), 1)

      new_entry = %{
        entry
        | # A rejected request does not consume a window slot.
          timestamps: active,
          strikes: new_strikes,
          last_strike_at: now,
          # The cooldown ends exactly retry_after past the moment the strike
          # was issued.
          cooldown_end: now + retry_after,
          window_ms: window_ms
      }

      {:reply, {:error, :rate_limited, retry_after, new_strikes},
       %{state | keys: Map.put(state.keys, key, new_entry)}}
    end
  end

  defp ladder_value(ladder, strike_n) when strike_n >= 1 do
    idx = min(strike_n - 1, length(ladder) - 1)
    Enum.at(ladder, idx)
  end

  defp decay_strikes(%{strikes: 0} = entry, _now, _window_ms), do: entry
  defp decay_strikes(%{last_strike_at: nil} = entry, _now, _window_ms), do: entry

  defp decay_strikes(entry, now, window_ms) do
    decay_period = window_ms * 10
    elapsed = now - entry.last_strike_at
    forgive = div(elapsed, decay_period)

    cond do
      forgive <= 0 ->
        entry

      forgive >= entry.strikes ->
        empty_entry()

      true ->
        new_strikes = entry.strikes - forgive
        new_last = entry.last_strike_at + forgive * decay_period

        # Decay forgives cooldowns: once any strike decays, an outstanding
        # cooldown is cancelled and the next request is evaluated against the
        # normal sliding-window limit.
        %{
          entry
          | strikes: new_strikes,
            last_strike_at: new_last,
            cooldown_end: nil
        }
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      state.keys
      |> Enum.reject(fn {_key, entry} -> removable?(entry, now) end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # A key is removed only when it has become indistinguishable from a
  # never-seen key: every timestamp has expired (judged against the window the
  # key was last checked with), the strike count has fully decayed, and no
  # cooldown is outstanding. Decay is computed here only to DECIDE removal —
  # retained entries keep their stored state, so decay still materializes
  # lazily at the next `check`.
  defp removable?(%{window_ms: nil}, _now), do: false

  defp removable?(entry, now) do
    decayed = decay_strikes(entry, now, entry.window_ms)
    window_start = now - entry.window_ms

    Enum.all?(decayed.timestamps, fn ts -> ts <= window_start end) and
      decayed.strikes == 0 and
      (decayed.cooldown_end == nil or decayed.cooldown_end <= now)
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```