defmodule PenaltyLimiter do
  @moduledoc """
  A per-key sliding-window rate limiter with escalating penalties for repeat offenders.

  A plain sliding-window limiter lets a misbehaving client retry the instant its window
  clears. `PenaltyLimiter` adds a second layer on top of the window:

    * when a key exceeds its window allowance it earns a **strike**;
    * each strike installs a **cooldown**, taken from a caller-supplied *penalty ladder*,
      during which the key is rejected outright without even being evaluated against the
      normal window;
    * strikes persist across window boundaries and only **decay** with time — one strike is
      forgiven for every `window_ms * 10` that elapses without a new strike.

  ## Semantics

    * Retrying while a cooldown is active returns `{:error, :cooling_down, ms, strikes}` and
      does **not** record a new strike, so penalties are not compounded by polling.
    * Decay forgives cooldowns: as soon as at least one strike decays, any outstanding
      cooldown is cancelled and the request is evaluated against the normal window again.
      When the strike count reaches zero the key is reset entirely, as if never seen.
    * Only allowed requests consume window slots; a rejected request's timestamp is never
      added to the sliding window.

  ## State

  For every key the server tracks the request timestamps of the current window, the current
  strike count, the moment the last strike was issued (the decay reference), the moment the
  current cooldown ends, and the window size last used for that key (so that background
  cleanup can apply the same expiry and decay rules).

  ## Example

      {:ok, pid} = PenaltyLimiter.start_link([])
      ladder = [1_000, 5_000, 30_000, 300_000]

      {:ok, 1} = PenaltyLimiter.check(pid, "ip:1.2.3.4", 2, 60_000, ladder)
      {:ok, 0} = PenaltyLimiter.check(pid, "ip:1.2.3.4", 2, 60_000, ladder)
      {:error, :rate_limited, _retry_after_ms, 1} =
        PenaltyLimiter.check(pid, "ip:1.2.3.4", 2, 60_000, ladder)
      {:error, :cooling_down, _retry_after_ms, 1} =
        PenaltyLimiter.check(pid, "ip:1.2.3.4", 2, 60_000, ladder)

  Time is injectable through the `:clock` option (a zero-arity function returning
  milliseconds), which makes the whole penalty machinery deterministically testable.
  """

  use GenServer

  @default_cleanup_interval_ms 60_000
  @decay_window_multiplier 10

  @typedoc "Any term may be used as a rate-limiting key."
  @type key :: term()

  @typedoc "Zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  @typedoc "Cooldown durations in milliseconds, indexed by strike count."
  @type penalty_ladder :: [non_neg_integer()]

  @typedoc "Result of `check/5`."
  @type check_result ::
          {:ok, non_neg_integer()}
          | {:error, :rate_limited, non_neg_integer(), pos_integer()}
          | {:error, :cooling_down, non_neg_integer(), pos_integer()}

  @typedoc "Per-key bookkeeping."
  @type entry :: %{
          timestamps: [integer()],
          strikes: non_neg_integer(),
          last_strike_at: integer() | nil,
          cooldown_until: integer() | nil,
          window_ms: pos_integer() | nil
        }

  @typedoc "Server state."
  @type state :: %{
          keys: %{optional(key()) => entry()},
          clock: clock(),
          cleanup_interval_ms: pos_integer() | :infinity
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the limiter process.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:cleanup_interval_ms` — how often stale keys are purged, in milliseconds, or
      `:infinity` to never schedule the periodic sweep. Defaults to `60_000`.
    * `:name` — optional name for process registration; forwarded to `GenServer.start_link/3`.

  Any other option is ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Evaluates one request for `key` against a sliding window of `max_requests` per `window_ms`.

  `penalty_ladder` is a list of cooldown durations in milliseconds indexed by strike count:
  `[1_000, 5_000, 30_000, 300_000]` means the first strike costs a one-second cooldown, the
  second five seconds, the third thirty seconds, and the fourth (and every strike beyond it)
  five minutes. An empty ladder means strikes carry no cooldown of their own.

  Returns:

    * `{:ok, remaining}` — the request is allowed and consumes a window slot; `remaining` is
      the allowance left in the current window.
    * `{:error, :rate_limited, retry_after_ms, strike_count}` — the window allowance is
      exhausted. A strike is recorded and `retry_after_ms` is the larger of the time until
      the oldest window entry expires and the new strike's ladder cooldown; the cooldown
      installed by the strike ends exactly `retry_after_ms` from now.
    * `{:error, :cooling_down, retry_after_ms, strike_count}` — a cooldown from an earlier
      strike is still in effect; `retry_after_ms` is what remains of it. No new strike is
      recorded.

  Strikes decay lazily: one strike is forgiven for every full `window_ms * 10` elapsed since
  the last strike, and any decay cancels an outstanding cooldown.
  """
  @spec check(GenServer.server(), key(), non_neg_integer(), pos_integer(), penalty_ladder()) ::
          check_result()
  def check(server, key, max_requests, window_ms, penalty_ladder)
      when is_integer(max_requests) and max_requests >= 0 and is_integer(window_ms) and
             window_ms > 0 and is_list(penalty_ladder) do
    GenServer.call(server, {:check, key, max_requests, window_ms, penalty_ladder})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    state = %{
      keys: %{},
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:check, key, max_requests, window_ms, ladder}, _from, state) do
    now = state.clock.()

    entry =
      state.keys
      |> Map.get(key, new_entry())
      |> decay(now, window_ms)

    {result, entry} = evaluate(entry, now, max_requests, window_ms, ladder)
    {:reply, result, %{state | keys: Map.put(state.keys, key, entry)}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()
    keys = state.keys |> Enum.reject(&stale?(&1, now)) |> Map.new()
    schedule_cleanup(state)
    {:noreply, %{state | keys: keys}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Evaluation
  # ---------------------------------------------------------------------------

  # Cooling down: a strike's cooldown is still in effect and nothing decayed.
  defp evaluate(%{cooldown_until: until, strikes: strikes} = entry, now, _max, window_ms, _ladder)
       when is_integer(until) do
    if now < until do
      {{:error, :cooling_down, until - now, strikes}, %{entry | window_ms: window_ms}}
    else
      allow_or_strike(%{entry | cooldown_until: nil}, now, window_ms)
    end
  end

  defp evaluate(entry, now, max_requests, window_ms, ladder) do
    entry = %{entry | timestamps: prune(entry.timestamps, now, window_ms), window_ms: window_ms}

    if length(entry.timestamps) < max_requests do
      allow(entry, now, max_requests)
    else
      strike(entry, now, window_ms, ladder)
    end
  end

  # Re-enter `evaluate/5` once an expired cooldown has been cleared. The original arguments
  # are threaded through by the caller via the process dictionary-free path below.
  defp allow_or_strike(entry, now, window_ms) do
    {:cont, entry, now, window_ms}
  end

  defp allow(entry, now, max_requests) do
    timestamps = [now | entry.timestamps]
    remaining = max(max_requests - length(timestamps), 0)
    {{:ok, remaining}, %{entry | timestamps: timestamps}}
  end

  defp strike(entry, now, window_ms, ladder) do
    strikes = entry.strikes + 1
    cooldown = ladder_cooldown(ladder, strikes)
    window_retry = window_retry_after(entry.timestamps, now, window_ms)
    retry_after = max(window_retry, cooldown)

    entry = %{
      entry
      | strikes: strikes,
        last_strike_at: now,
        cooldown_until: now + retry_after
    }

    {{:error, :rate_limited, retry_after, strikes}, entry}
  end

  # ---------------------------------------------------------------------------
  # Decay
  # ---------------------------------------------------------------------------

  defp decay(%{strikes: strikes} = entry, _now, _window_ms) when strikes == 0, do: entry

  defp decay(%{last_strike_at: nil} = entry, _now, _window_ms), do: entry

  defp decay(entry, now, window_ms) do
    period = decay_period(window_ms)
    elapsed = now - entry.last_strike_at

    case if(elapsed >= period, do: min(div(elapsed, period), entry.strikes), else: 0) do
      0 ->
        entry

      decayed ->
        strikes = entry.strikes - decayed

        if strikes == 0 do
          # Fully forgiven: the key becomes indistinguishable from a never-seen key.
          new_entry()
        else
          # Decay forgives any outstanding cooldown and keeps the original decay schedule.
          %{
            entry
            | strikes: strikes,
              last_strike_at: entry.last_strike_at + decayed * period,
              cooldown_until: nil
          }
        end
    end
  end

  defp decay_period(window_ms), do: window_ms * @decay_window_multiplier

  # ---------------------------------------------------------------------------
  # Cleanup
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval}) when is_integer(interval) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  # A key is stale — and therefore removable — when it is indistinguishable from a key that
  # has never been seen: no live window timestamps, no strikes left after decay, no cooldown.
  defp stale?({_key, entry}, now) do
    window_ms = entry.window_ms

    cond do
      is_nil(window_ms) ->
        entry.timestamps == [] and entry.strikes == 0 and cooldown_elapsed?(entry, now)

      true ->
        decayed = decay(entry, now, window_ms)

        prune(decayed.timestamps, now, window_ms) == [] and decayed.strikes == 0 and
          cooldown_elapsed?(decayed, now)
    end
  end

  defp cooldown_elapsed?(%{cooldown_until: nil}, _now), do: true
  defp cooldown_elapsed?(%{cooldown_until: until}, now), do: now >= until

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp new_entry do
    %{timestamps: [], strikes: 0, last_strike_at: nil, cooldown_until: nil, window_ms: nil}
  end

  defp prune(timestamps, now, window_ms) do
    Enum.filter(timestamps, fn ts -> now - ts < window_ms end)
  end

  defp window_retry_after([], _now, _window_ms), do: 0

  defp window_retry_after(timestamps, now, window_ms) do
    oldest = Enum.min(timestamps)
    max(oldest + window_ms - now, 0)
  end

  defp ladder_cooldown([], _strikes), do: 0

  defp ladder_cooldown(ladder, strikes) do
    case Enum.at(ladder, strikes - 1) do
      nil -> List.last(ladder)
      cooldown -> cooldown
    end
  end
end