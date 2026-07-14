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
            # Match pattern: {player_id, OldScore}
            {player_id, :"$1"},
            # Guard: new score > existing score
            [{:>, score, :"$1"}],
            # Action: replace the whole object with the new record
            [{:const, {player_id, score}}]
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

Write me an Elixir module called `OrderedLeaderboard` that maintains an all-time-high leaderboard using ETS (Erlang Term Storage), but with **deterministic tie-breaking** and **unique ordinal ranks**: when two players share the same score, whoever reached that score *first* ranks higher, and every player gets a distinct 1-based position (no shared ranks).

To make this efficient and deterministic, use an ETS `:ordered_set` whose key is a composite tuple that encodes score-descending, then arrival order. Serialize writes through a small GenServer that owns the tables (so the composite key and a global sequence counter stay consistent), while reads go straight to the public ETS tables for lock-free concurrency.

I need these functions in the public API:
- `OrderedLeaderboard.new(board_name)` to create a leaderboard. `board_name` is an atom used to name
  the underlying ETS table. Return `{:ok, board}` where `board` is an identifier (it may be a map or
  struct holding the server and table handles) that you pass to the other functions.
- `OrderedLeaderboard.submit_score(board, player_id, score)` to submit a score. `player_id` can be any
  term; `score` is a number. Only the player's all-time highest score is kept: a strictly higher score
  overwrites the previous one (and, for tie-breaking purposes, counts as being "reached" at submission
  time); a lower-or-equal score is a no-op. Always return `:ok`.
- `OrderedLeaderboard.top(board, n)` to return the top N players, as `{player_id, score}` tuples in
  final leaderboard order (score descending; ties broken by earliest arrival at that score). If fewer
  than N players exist, return all of them. Reads must traverse the ordered set in key order.
- `OrderedLeaderboard.rank(board, player_id)` to return `{:ok, rank, score}` where `rank` is the
  player's unique 1-based ordinal position in that same total order, or `{:error, :not_found}` if the
  player does not exist.

Implementation requirements:
- The main store is an ETS `:ordered_set`, created `:public`, with a composite key of the form
  `{negated_score, sequence, player_id}` so ETS's native key ordering yields score-descending then
  arrival-ascending. Maintain a secondary `:set` index from `player_id` to its current composite key
  so you can find and delete a player's old entry on update.
- A GenServer owns both tables and serializes `submit_score/3`, assigning a monotonically increasing
  sequence number so tie-breaking is consistent. `top/2` and `rank/2` must NOT call the GenServer —
  they read the public ETS tables directly.
- `rank/2` returns unique ordinal positions (tied scores get distinct, deterministic ranks), which is
  a deliberate contrast to competition ranking.
- Do not use any external dependencies — only the OTP standard library.

Give me the complete module in a single file.
