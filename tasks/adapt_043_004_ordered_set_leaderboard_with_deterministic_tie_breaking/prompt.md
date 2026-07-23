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

# Design brief: `OrderedLeaderboard`

## Problem

We need an all-time-high leaderboard for Elixir, backed by ETS (Erlang Term Storage), that behaves
**deterministically** under ties and hands out **unique ordinal ranks**. Two players holding the same
score must not be ordered arbitrarily: whoever reached that score *first* ranks higher. And no two
players may share a position — every player gets a distinct 1-based position (no shared ranks).

## Constraints

- The main store is an ETS `:ordered_set`, created `:public`, whose key is a composite tuple of the
  form `{negated_score, sequence, player_id}`. Encoding score-descending then arrival order into the
  key means ETS's native key ordering already yields score-descending then arrival-ascending — no
  sorting pass required.
- A secondary `:set` index maps `player_id` to its current composite key, so a player's old entry can
  be found and deleted on update.
- Writes are serialized through a small GenServer that owns both tables, so the composite key and a
  global sequence counter stay consistent. That GenServer serializes `submit_score/3` and assigns a
  monotonically increasing sequence number, making tie-breaking consistent.
- Reads go straight to the public ETS tables for lock-free concurrency: `top/2` and `rank/2` must NOT
  call the GenServer.
- No external dependencies — only the OTP standard library.
- Deliverable: the complete module in a single file, named `OrderedLeaderboard`.

## Required interface

1. `OrderedLeaderboard.new(board_name)` — creates a leaderboard. `board_name` is an atom used to name
   the underlying ETS table. Returns `{:ok, board}` where `board` is an identifier (it may be a map or
   struct holding the server and table handles) that you pass to the other functions.
2. `OrderedLeaderboard.submit_score(board, player_id, score)` — submits a score. `player_id` can be any
   term; `score` is a number. Only the player's all-time highest score is kept: a strictly higher score
   overwrites the previous one (and, for tie-breaking purposes, counts as being "reached" at submission
   time); a lower-or-equal score is a no-op. Always returns `:ok`.
3. `OrderedLeaderboard.top(board, n)` — returns the top N players as `{player_id, score}` tuples in
   final leaderboard order (score descending; ties broken by earliest arrival at that score). If fewer
   than N players exist, returns all of them. Reads must traverse the ordered set in key order.
4. `OrderedLeaderboard.rank(board, player_id)` — returns `{:ok, rank, score}` where `rank` is the
   player's unique 1-based ordinal position in that same total order, or `{:error, :not_found}` if the
   player does not exist.

## Acceptance criteria

- Ordering is deterministic: equal scores resolve by earliest arrival at that score, ranking the
  earlier arriver higher.
- `rank/2` returns unique ordinal positions — tied scores get distinct, deterministic ranks. This is a
  deliberate contrast to competition ranking.
- A submission at or below a player's stored high score leaves the board unchanged; a strictly higher
  one replaces the old entry and re-times the player's arrival.
- `top/2` and `rank/2` are answered entirely from the public ETS tables, with no GenServer call on the
  read path.
- The implementation uses an ETS `:ordered_set` for the main store plus a `:set` player index, both
  owned by the GenServer, and compiles and runs with only the OTP standard library.
