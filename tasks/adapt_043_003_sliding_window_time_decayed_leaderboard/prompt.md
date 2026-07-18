# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Leaderboard do
  @moduledoc """
  A leaderboard backed by an ETS table.

  ## Tie-breaking / Rank contract

  `rank/2` uses **standard competition ranking** ("1224" ranking): all players
  with the same score receive the same rank, and the next rank is bumped by the
  full size of the tied group.  For example, if two players share rank 1, the
  next player is rank 3.  The ordering among players with an identical score is
  unspecified and may change between calls.
  """

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # With :named_table, :ets.new/2 returns the table's name atom, and every
  # operation below addresses the table by that name.
  @type board :: atom()
  @type player_id :: term()
  @type score :: number()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new leaderboard backed by a public ETS set named `board_name`.

  Returns `{:ok, board}` where `board` is the ETS table identifier that must be
  passed to all other functions.
  """
  @spec new(atom()) :: {:ok, board()}
  def new(board_name) when is_atom(board_name) do
    board = :ets.new(board_name, [:set, :public, :named_table, read_concurrency: true])
    {:ok, board}
  end

  @doc """
  Submits `score` for `player_id`.

  Only the player's all-time highest score is kept:
  - If the player is new, the score is inserted.
  - If the new score is strictly greater than the stored one, it overwrites the
    previous entry.
  - If the new score is less than or equal to the stored one, this is a no-op.

  Always returns `:ok`.
  """
  @spec submit_score(board(), player_id(), score()) :: :ok
  def submit_score(board, player_id, score) do
    # :ets.update_counter/4 cannot handle floats, so we use a CAS loop instead.
    # insert_new/2 succeeds only when the key is absent — giving us a fast path
    # for first-time submissions with no race conditions.
    case :ets.insert_new(board, {player_id, score}) do
      true ->
        # Fresh insertion — we're done.
        :ok

      false ->
        # Key already exists; update only when the new score is strictly higher.
        # :ets.select_replace/2 performs the conditional overwrite atomically
        # on the ETS level, so no GenServer is needed.
        match_spec = [
          {
            # Match pattern: bind key and score as variables. Embedding the raw
            # player_id in the head would let match-spec-significant atoms
            # (:_, :"$1", …) match as wildcards instead of as themselves — and
            # the contract allows ANY term as a player id.
            {:"$1", :"$2"},
            # Guard: exactly this key (as a literal term) AND a higher score.
            [{:andalso, {:"=:=", :"$1", {:const, player_id}}, {:>, score, :"$2"}}],
            # Action: rebuild the record around the BOUND key variable —
            # select_replace statically requires the key position to be
            # provably unchanged, so :"$1" (not a literal copy) must stay.
            [{{:"$1", {:const, score}}}]
          }
        ]

        :ets.select_replace(board, match_spec)
        :ok
    end
  end

  @doc """
  Returns the top `n` players sorted by score descending.

  Fewer than `n` tuples are returned when the leaderboard has fewer than `n`
  entries.  Each element is a `{player_id, score}` tuple.
  """
  @spec top(board(), non_neg_integer()) :: [{player_id(), score()}]
  def top(_board, 0), do: []

  def top(board, n) when is_integer(n) and n > 0 do
    board
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_pid, score} -> score end, :desc)
    |> Enum.take(n)
  end

  @doc """
  Returns the rank and score of `player_id`.

  Uses **standard competition ranking**: tied players share the same rank, and
  the rank of the next lower group is bumped by the full size of the tied group
  (e.g. two players at rank 1 → next player is rank 3).

  Returns:
  - `{:ok, rank, score}` — player exists; `rank` is 1-based.
  - `{:error, :not_found}` — player has never submitted a score.
  """
  @spec rank(board(), player_id()) :: {:ok, pos_integer(), score()} | {:error, :not_found}
  def rank(board, player_id) do
    case :ets.lookup(board, player_id) do
      [] ->
        {:error, :not_found}

      [{^player_id, player_score}] ->
        # Count how many players have a score strictly greater than this one.
        # That count + 1 gives us the 1-based standard competition rank.
        match_spec = [
          {
            {:_, :"$1"},
            [{:>, :"$1", player_score}],
            [true]
          }
        ]

        players_above = :ets.select_count(board, match_spec)
        rank = players_above + 1
        {:ok, rank, player_score}
    end
  end
end
```

## New specification

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
