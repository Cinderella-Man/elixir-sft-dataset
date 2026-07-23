# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `score` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# Design brief: `SlidingWindowLeaderboard`

## Problem

An all-time leaderboard is the wrong shape for a game where recency matters. We need a **time-decayed** leaderboard in Elixir, backed by ETS (Erlang Term Storage), in which a player's leaderboard score is the sum of the points from scoring events that occurred within a rolling time window (e.g. the last 60 seconds). Old events "fall off" the window and stop counting.

## Constraints

- Time is always passed in explicitly as a millisecond integer `now` so the module is fully deterministic and testable — never read the system clock.
- Use ETS as the backing store. Because a player accumulates many events over time, use a `:duplicate_bag` table keyed by `player_id`, storing one row per event, created `:public`.
- Recording an event must be a single atomic `:ets.insert/2` so multiple processes can record concurrently without coordination or lost writes. Do not use a GenServer.
- An event exactly at the cutoff (`timestamp == now - window_ms`) is considered expired.
- Do not use any external dependencies — only the OTP standard library.
- The module must be named `SlidingWindowLeaderboard`.

## Required public API

1. `SlidingWindowLeaderboard.new(board_name, window_ms)` — creates a leaderboard. `board_name` is an atom naming the underlying ETS table, `window_ms` is a positive integer window size in milliseconds. Returns `{:ok, board}` where `board` is an identifier you pass to the other functions. Invalid arguments are rejected by raising a `FunctionClauseError` (enforce with guards): a non-atom `board_name`, or a `window_ms` that is not a positive integer — `0`, negatives, and floats such as `100.0` must all raise.
2. `SlidingWindowLeaderboard.record(board, player_id, points, now)` — records a scoring event of `points` (a number, integer or float) for `player_id` at timestamp `now`. Returns `:ok`. A non-number `points` (e.g. a string) must raise a `FunctionClauseError`.
3. `SlidingWindowLeaderboard.score(board, player_id, now)` — computes a player's **active** score as of `now`: the sum of points from that player's events whose timestamp is strictly greater than `now - window_ms`. Returns `{:ok, active_score}`. A player whose active events sum to `0` is still found — return `{:ok, 0}`. If the player has no active events (they never recorded anything, or all their events have expired), return `{:error, :not_found}`.
4. `SlidingWindowLeaderboard.top(board, n, now)` — returns the top N players by active score at `now`, sorted descending, as `{player_id, active_score}` tuples. Players with no active events must not appear. If fewer than N active players exist, return all of them.
5. `SlidingWindowLeaderboard.rank(board, player_id, now)` — returns `{:ok, rank, active_score}` for a player at `now` (1-based, standard competition ranking, tied active scores share a rank), or `{:error, :not_found}` if the player has no active events.
6. `SlidingWindowLeaderboard.prune(board, now)` — garbage-collects: permanently deletes every event whose timestamp is `<= now - window_ms`. Returns the number of events deleted.

## Acceptance criteria

- All six functions above exist with exactly the described return shapes and error tuples.
- Guard-enforced `FunctionClauseError` raises fire for a non-atom `board_name`, for `window_ms` values of `0`, negatives, and floats such as `100.0`, and for non-number `points`.
- Window arithmetic is exclusive at the lower bound: events with `timestamp > now - window_ms` count; an event at exactly `now - window_ms` is expired.
- Storage is a `:public`, `:duplicate_bag` ETS table keyed by `player_id` with one row per event, and writes go through a single atomic `:ets.insert/2` with no GenServer involved.
- No external dependencies are used — OTP standard library only.
- Delivery: the complete module in a single file.

## The module with `score` missing

```elixir
defmodule SlidingWindowLeaderboard do
  @moduledoc """
  A time-decayed leaderboard backed by an ETS `:duplicate_bag`.

  Each scoring event is stored as its own row `{player_id, timestamp, points}`.
  A player's *active* score at time `now` is the sum of points from events whose
  timestamp is strictly greater than `now - window_ms`; older events "fall off"
  the window and no longer count.

  Time is always supplied by the caller as a millisecond integer, so the module
  is fully deterministic.  Recording is a single atomic `:ets.insert/2`, so many
  processes may record concurrently with no coordination and no lost writes.

  ## Rank contract

  `rank/3` uses standard competition ("1224") ranking over active scores: tied
  players share a rank and the next lower group is bumped by the tie-group size.
  """

  @type board :: {atom(), pos_integer()}
  @type player_id :: term()

  @doc """
  Creates a new sliding-window leaderboard with window `window_ms` milliseconds.
  """
  @spec new(atom(), pos_integer()) :: {:ok, board()}
  def new(board_name, window_ms)
      when is_atom(board_name) and is_integer(window_ms) and window_ms > 0 do
    tid =
      :ets.new(board_name, [
        :duplicate_bag,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, {tid, window_ms}}
  end

  @doc """
  Records a scoring event of `points` for `player_id` at `now`.  Atomic insert.
  """
  @spec record(board(), player_id(), number(), integer()) :: :ok
  def record({tid, _window}, player_id, points, now)
      when is_number(points) and is_integer(now) do
    :ets.insert(tid, {player_id, now, points})
    :ok
  end

  def score(board, player_id, now) do
    # TODO
  end

  @doc """
  Returns the top `n` active players at `now`, sorted by active score descending.
  """
  @spec top(board(), non_neg_integer(), integer()) :: [{player_id(), number()}]
  def top(_board, 0, _now), do: []

  def top(board, n, now) when is_integer(n) and n > 0 do
    board
    |> active_scores(now)
    |> Enum.sort_by(fn {_p, s} -> s end, :desc)
    |> Enum.take(n)
  end

  @doc """
  Returns `{:ok, rank, active_score}` (1-based competition ranking) at `now`, or
  `{:error, :not_found}` when the player has no active events.
  """
  @spec rank(board(), player_id(), integer()) ::
          {:ok, pos_integer(), number()} | {:error, :not_found}
  def rank(board, player_id, now) do
    scores = active_scores(board, now)

    case Enum.find(scores, fn {p, _s} -> p == player_id end) do
      nil ->
        {:error, :not_found}

      {_p, s} ->
        above = Enum.count(scores, fn {_p2, other} -> other > s end)
        {:ok, above + 1, s}
    end
  end

  @doc """
  Deletes every event with `timestamp <= now - window_ms`.  Returns the count.
  """
  @spec prune(board(), integer()) :: non_neg_integer()
  def prune({tid, window}, now) when is_integer(now) do
    cutoff = now - window
    match_spec = [{{:_, :"$1", :_}, [{:"=<", :"$1", cutoff}], [true]}]
    :ets.select_delete(tid, match_spec)
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  # Returns [{player_id, active_score}] for every player with at least one event
  # whose timestamp is strictly greater than (now - window).
  defp active_scores({tid, window}, now) do
    cutoff = now - window

    tid
    |> :ets.tab2list()
    |> Enum.filter(fn {_p, ts, _pts} -> ts > cutoff end)
    |> Enum.group_by(fn {p, _ts, _pts} -> p end, fn {_p, _ts, pts} -> pts end)
    |> Enum.map(fn {p, points} -> {p, Enum.sum(points)} end)
  end
end
```

Reply with `score` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
