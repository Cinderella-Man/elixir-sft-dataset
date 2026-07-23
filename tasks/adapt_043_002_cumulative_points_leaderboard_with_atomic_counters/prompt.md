# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

Write me an Elixir module called `CumulativeLeaderboard` that maintains a leaderboard using ETS (Erlang Term Storage), where — unlike an all-time-high leaderboard — a player's score is the **running sum** of all the points they have been awarded over time.

I need these functions in the public API:
- `CumulativeLeaderboard.new(board_name)` to create a new leaderboard. `board_name` is an atom
  used to name the underlying ETS table. Return `{:ok, board}` where `board` is a
  reference/identifier you can pass to the other functions.
- `CumulativeLeaderboard.add_points(board, player_id, points)` to award `points` to a player.
  `player_id` can be any term (string, integer, atom). `points` must be an **integer** (it may be
  negative to deduct points). If the player is new, their total starts from 0 and `points` is added
  (so a first award of 0 registers the player with a total of 0). If the player already exists,
  `points` is added to the existing total. Return `{:ok, new_total}` with the player's total after
  applying the increment. If `points` is not an integer (e.g. a float or a string), the call must
  raise a `FunctionClauseError` (guard the argument with `when is_integer(points)`), and the player
  must not be registered.
- `CumulativeLeaderboard.total(board, player_id)` to read a player's current total. Return
  `{:ok, total}` or `{:error, :not_found}` if the player has never been awarded points.
- `CumulativeLeaderboard.top(board, n)` to retrieve the top N players by total, sorted descending.
  Return a list of `{player_id, total}` tuples. If fewer than N players exist, return all of them
  (and `[]` when the board is empty). Negative totals sort below zero and positive totals.
  Ties can be returned in any order.
- `CumulativeLeaderboard.rank(board, player_id)` to get a player's rank and total. Return
  `{:ok, rank, total}` where rank is 1-based (rank 1 = highest total), using standard competition
  ranking (tied players share the same rank, and the next lower group is bumped by the full size of
  the tied group — e.g. two players tied at rank 1 make the next player rank 3). If the player does
  not exist, return `{:error, :not_found}`.

Implementation requirements:
- Use ETS as the backing store, a `:set` table (one row per player), created `:public`.
- Because scores accumulate, `add_points/3` MUST be a lock-free atomic increment — use
  `:ets.update_counter/4` with a default object so concurrent awards to the same player never lose
  updates. Do not use a GenServer and do not do a read-modify-write in Elixir.
- All operations must be correct when called from multiple processes concurrently: if 100 processes
  each award 1 point to the same player, the final total must be exactly 100.
- Distinct boards must not share state, and different `player_id` types (e.g. `"1"`, `1`, `:one`)
  must be treated as independent players.
- Do not use any external dependencies — only the OTP standard library.

Give me the complete module in a single file.
