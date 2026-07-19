# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `top` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `SlidingWindowLeaderboard` that maintains a **time-decayed** leaderboard using ETS (Erlang Term Storage). Instead of an all-time score, a player's leaderboard score is the sum of the points from scoring events that occurred within a rolling time window (e.g. the last 60 seconds). Old events "fall off" the window and stop counting.

Time is always passed in explicitly as a millisecond integer `now` so the module is fully deterministic and testable — never read the system clock.

I need these functions in the public API:
- `SlidingWindowLeaderboard.new(board_name, window_ms)` to create a leaderboard. `board_name` is an
  atom naming the underlying ETS table, `window_ms` is a positive integer window size in
  milliseconds. Return `{:ok, board}` where `board` is an identifier you pass to the other functions.
  Reject invalid arguments by raising a `FunctionClauseError` (enforce with guards): a non-atom
  `board_name`, or a `window_ms` that is not a positive integer — `0`, negatives, and floats such as
  `100.0` must all raise.
- `SlidingWindowLeaderboard.record(board, player_id, points, now)` to record a scoring event of
  `points` (a number, integer or float) for `player_id` at timestamp `now`. Return `:ok`. A
  non-number `points` (e.g. a string) must raise a `FunctionClauseError`.
- `SlidingWindowLeaderboard.score(board, player_id, now)` to compute a player's **active** score as
  of `now`: the sum of points from that player's events whose timestamp is strictly greater than
  `now - window_ms`. Return `{:ok, active_score}`. A player whose active events sum to `0` is still
  found — return `{:ok, 0}`. If the player has no active events (they never
  recorded anything, or all their events have expired), return `{:error, :not_found}`.
- `SlidingWindowLeaderboard.top(board, n, now)` to return the top N players by active score at `now`,
  sorted descending, as `{player_id, active_score}` tuples. Players with no active events must not
  appear. If fewer than N active players exist, return all of them.
- `SlidingWindowLeaderboard.rank(board, player_id, now)` to return `{:ok, rank, active_score}` for a
  player at `now` (1-based, standard competition ranking, tied active scores share a rank), or
  `{:error, :not_found}` if the player has no active events.
- `SlidingWindowLeaderboard.prune(board, now)` to garbage-collect: permanently delete every event
  whose timestamp is `<= now - window_ms`. Return the number of events deleted.

Implementation requirements:
- Use ETS as the backing store. Because a player accumulates many events over time, use a
  `:duplicate_bag` table keyed by `player_id`, storing one row per event, created `:public`.
- Recording an event must be a single atomic `:ets.insert/2` so multiple processes can record
  concurrently without coordination or lost writes. Do not use a GenServer.
- An event exactly at the cutoff (`timestamp == now - window_ms`) is considered expired.
- Do not use any external dependencies — only the OTP standard library.

Give me the complete module in a single file.

## The module with `top` missing

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

  @type board :: {:ets.tid(), pos_integer()}
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

  @doc """
  Returns `{:ok, active_score}` for a player at `now`, or `{:error, :not_found}`
  when the player has no active (unexpired) events.
  """
  @spec score(board(), player_id(), integer()) :: {:ok, number()} | {:error, :not_found}
  def score(board, player_id, now) do
    case Enum.find(active_scores(board, now), fn {p, _s} -> p == player_id end) do
      nil -> {:error, :not_found}
      {_p, s} -> {:ok, s}
    end
  end

  def top(_board, 0, _now) do
    # TODO
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

Give me only the complete implementation of `top` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
