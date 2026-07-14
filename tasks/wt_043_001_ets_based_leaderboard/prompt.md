# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir module called `Leaderboard` that maintains a leaderboard using ETS (Erlang Term Storage).

I need these functions in the public API:
- `Leaderboard.new(board_name)` to create a new leaderboard. `board_name` is an atom used
  to name the underlying ETS table. It should return `{:ok, board}` where `board` is a
  reference/identifier you can pass to the other functions.
- `Leaderboard.submit_score(board, player_id, score)` to submit a score for a player.
  `player_id` can be any term (string, integer, atom). `score` is a number. Only the
  player's all-time highest score should be kept — submitting a lower score must be a
  no-op, submitting a higher score must overwrite the previous one. Always return `:ok`.
- `Leaderboard.top(board, n)` to retrieve the top N players by score, sorted descending.
  Return a list of `{player_id, score}` tuples. If fewer than N players exist, return all
  of them. Ties in score can be returned in any order.
- `Leaderboard.rank(board, player_id)` to get a specific player's rank and score. Return
  `{:ok, rank, score}` where rank is 1-based (rank 1 = highest score). If the player does
  not exist, return `{:error, :not_found}`. Ties should give the same rank to all tied
  players (dense ranking is not required — any consistent tie-breaking is fine as long as
  the contract is documented).

Implementation requirements:
- Use ETS as the backing store. The table should be of type `:set` (one row per player).
- `new/1` should create a public ETS table so callers don't have to worry about process
  ownership for the purposes of this exercise.
- All operations must work correctly when called from multiple processes concurrently.
  Since ETS provides concurrency for free on `:public` tables, you do not need a GenServer
  unless you want one.
- Do not use any external dependencies — only the OTP standard library.

Give me the complete module in a single file.

## Module under test

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
