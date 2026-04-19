Implement the private `decay_strikes/3` function. It should reduce the strike count based on elapsed time.

Use a decay period of `window_ms * 10`. For every full decay period that has passed since `last_strike_at`, reduce the strike count by one.

If the strike count reaches zero, reset the entry to a clean state. If strikes still remain, update the `last_strike_at` to reflect the time accounted for by the decay and—crucially—clear the `cooldown_end` to ensure that stale penalties do not persist after a strike has decayed. 

If no time has passed or no strikes exist, return the entry unchanged.

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
      d when is_integer(d) and d > 0 -> :ok
      bad -> raise ArgumentError, "penalty ladder entries must be positive integers, got #{inspect(bad)}"
    end)

    GenServer.call(server, {:check, key, max_requests, window_ms, penalty_ladder})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  defp empty_entry do
    %{timestamps: [], strikes: 0, last_strike_at: nil, cooldown_end: nil}
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
    now = state.clock.()
    entry = Map.get(state.keys, key, empty_entry())

    # Step 1: decay strikes
    entry = decay_strikes(entry, now, window_ms)

    # ✅ FIX: expire cooldown if time has passed
    entry =
      if entry.cooldown_end && entry.cooldown_end <= now do
        %{entry | cooldown_end: nil}
      else
        entry
      end

    # Step 2: enforce cooldown if still active
    cond do
      entry.cooldown_end != nil and entry.cooldown_end > now ->
        retry_after = entry.cooldown_end - now

        {:reply, {:error, :cooling_down, retry_after, entry.strikes},
         %{state | keys: Map.put(state.keys, key, entry)}}

      true ->
        evaluate_window(state, key, entry, now, max_requests, window_ms, ladder)
    end
  end

  defp evaluate_window(state, key, entry, now, max_requests, window_ms, ladder) do
    window_start = now - window_ms
    
    # Highly efficient: stops traversing as soon as we hit expired timestamps
    active = Enum.take_while(entry.timestamps, fn ts -> ts > window_start end)
    count = length(active)

    if count < max_requests do
      # O(1) prepend
      new_entry = %{entry | timestamps: [now | active], cooldown_end: nil}
      remaining = max_requests - count - 1

      {:reply, {:ok, remaining}, %{state | keys: Map.put(state.keys, key, new_entry)}}
    else
      new_strikes = entry.strikes + 1
      cooldown_ms = ladder_value(ladder, new_strikes)

      # List.last is perfectly safe because monotonic time + prepending guarantees order
      oldest = List.last(active)
      window_retry = oldest + window_ms - now
      
      # Calculate the true retry duration
      retry_after = max(max(window_retry, cooldown_ms), 1)

      new_entry = %{
        entry
        | timestamps: active,          # Do NOT add 'now' for rejected requests
          strikes: new_strikes,
          last_strike_at: now,
          cooldown_end: now + retry_after # Fixed: Align stored state with returned value
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
    # TODO
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      Enum.reduce(state.keys, %{}, fn {key, entry}, acc ->
        # NEW: drop expired timestamps
        active = Enum.take_while(entry.timestamps, fn ts -> ts > now end)
        entry = %{entry | timestamps: active}

        cooldown_active = entry.cooldown_end != nil and entry.cooldown_end > now
        has_strikes = entry.strikes > 0
        has_timestamps = active != []

        if cooldown_active or has_strikes or has_timestamps do
          Map.put(acc, key, entry)
        else
          acc
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```