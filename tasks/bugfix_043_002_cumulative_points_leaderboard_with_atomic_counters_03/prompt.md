# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Design brief: `CumulativeLeaderboard`

## Problem

We need an Elixir module called `CumulativeLeaderboard` that maintains a leaderboard using ETS (Erlang Term Storage). Unlike an all-time-high leaderboard, a player's score here is the **running sum** of all the points they have been awarded over time.

## Constraints

- Use ETS as the backing store, a `:set` table (one row per player), created `:public`.
- Because scores accumulate, `add_points/3` MUST be a lock-free atomic increment — use `:ets.update_counter/4` with a default object so concurrent awards to the same player never lose updates. Do not use a GenServer and do not do a read-modify-write in Elixir.
- All operations must be correct when called from multiple processes concurrently: if 100 processes each award 1 point to the same player, the final total must be exactly 100.
- Distinct boards must not share state, and different `player_id` types (e.g. `"1"`, `1`, `:one`) must be treated as independent players.
- Do not use any external dependencies — only the OTP standard library.

## Required public API

1. `CumulativeLeaderboard.new(board_name)` — creates a new leaderboard. `board_name` is an atom used to name the underlying ETS table. Returns `{:ok, board}` where `board` is a reference/identifier you can pass to the other functions.
2. `CumulativeLeaderboard.add_points(board, player_id, points)` — awards `points` to a player. `player_id` can be any term (string, integer, atom). `points` must be an **integer** (it may be negative to deduct points). If the player is new, their total starts from 0 and `points` is added (so a first award of 0 registers the player with a total of 0). If the player already exists, `points` is added to the existing total. Returns `{:ok, new_total}` with the player's total after applying the increment. If `points` is not an integer (e.g. a float or a string), the call must raise a `FunctionClauseError` (guard the argument with `when is_integer(points)`), and the player must not be registered.
3. `CumulativeLeaderboard.total(board, player_id)` — reads a player's current total. Returns `{:ok, total}`, or `{:error, :not_found}` if the player has never been awarded points.
4. `CumulativeLeaderboard.top(board, n)` — retrieves the top N players by total, sorted descending. Returns a list of `{player_id, total}` tuples. If fewer than N players exist, return all of them (and `[]` when the board is empty). Negative totals sort below zero and positive totals. Ties can be returned in any order.
5. `CumulativeLeaderboard.rank(board, player_id)` — gets a player's rank and total. Returns `{:ok, rank, total}` where rank is 1-based (rank 1 = highest total), using standard competition ranking (tied players share the same rank, and the next lower group is bumped by the full size of the tied group — e.g. two players tied at rank 1 make the next player rank 3). If the player does not exist, returns `{:error, :not_found}`.

## Acceptance criteria

- All five functions above are present in the public API and behave exactly as specified, including the documented return shapes and the `{:error, :not_found}` cases.
- Non-integer `points` raises `FunctionClauseError` and leaves the player unregistered.
- Concurrent awards are never lost: 100 processes each awarding 1 point to the same player yields exactly 100.
- The increment path uses `:ets.update_counter/4` with a default object — no GenServer, no read-modify-write.
- Boards are isolated from one another, and `"1"`, `1`, and `:one` are independent players.
- Only the OTP standard library is used.
- Deliverable: the complete module in a single file.

## The buggy module

```elixir
defmodule CumulativeLeaderboard do
  @moduledoc """
  A cumulative-scoring leaderboard backed by an ETS table.

  A player's score is the running SUM of every award they have received.  Because
  awards accumulate, updates use `:ets.update_counter/4`, which performs the
  increment atomically at the ETS level — concurrent awards to the same player can
  never lose updates, and no GenServer or Elixir-level read-modify-write is needed.

  ## Rank contract

  `rank/2` uses standard competition ("1224") ranking: tied players share the same
  rank and the next lower group is bumped by the full size of the tied group.
  """

  @type board :: :ets.tid()
  @type player_id :: term()

  @doc """
  Creates a new cumulative leaderboard backed by a public ETS set named `board_name`.
  """
  @spec new(atom()) :: {:ok, board()}
  def new(board_name) when is_atom(board_name) do
    tid =
      :ets.new(board_name, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, tid}
  end

  @doc """
  Awards `points` (an integer, possibly negative) to `player_id`.

  New players start from a total of 0.  The increment is applied atomically via
  `:ets.update_counter/4`.  Returns `{:ok, new_total}`.
  """
  @spec add_points(board(), player_id(), integer()) :: {:ok, integer()}
  def add_points(board, player_id, points) when is_integer(points) do
    new_total = :ets.update_counter(board, player_id, points, {player_id, 1})
    {:ok, new_total}
  end

  @doc """
  Returns `{:ok, total}` for a player, or `{:error, :not_found}` if absent.
  """
  @spec total(board(), player_id()) :: {:ok, integer()} | {:error, :not_found}
  def total(board, player_id) do
    case :ets.lookup(board, player_id) do
      [] -> {:error, :not_found}
      [{^player_id, score}] -> {:ok, score}
    end
  end

  @doc """
  Returns the top `n` players by total, sorted descending.
  """
  @spec top(board(), non_neg_integer()) :: [{player_id(), integer()}]
  def top(_board, 0), do: []

  def top(board, n) when is_integer(n) and n > 0 do
    board
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_pid, score} -> score end, :desc)
    |> Enum.take(n)
  end

  @doc """
  Returns `{:ok, rank, total}` (1-based, standard competition ranking) or
  `{:error, :not_found}`.
  """
  @spec rank(board(), player_id()) :: {:ok, pos_integer(), integer()} | {:error, :not_found}
  def rank(board, player_id) do
    case :ets.lookup(board, player_id) do
      [] ->
        {:error, :not_found}

      [{^player_id, score}] ->
        match_spec = [{{:_, :"$1"}, [{:>, :"$1", score}], [true]}]
        above = :ets.select_count(board, match_spec)
        {:ok, above + 1, score}
    end
  end
end
```

## Failing test report

```
8 of 13 test(s) failed:

  * test first award initializes from zero
      
      
      match (=) failed
      code:  assert {:ok, 10} = CumulativeLeaderboard.add_points(board, "alice", 10)
      left:  {:ok, 10}
      right: {:ok, 11}
      

  * test points accumulate across awards
      
      
      match (=) failed
      code:  assert {:ok, 10} = CumulativeLeaderboard.add_points(board, "alice", 10)
      left:  {:ok, 10}
      right: {:ok, 11}
      

  * test negative running totals are valid
      
      
      match (=) failed
      code:  assert {:ok, -8} = CumulativeLeaderboard.add_points(board, "alice", -8)
      left:  {:ok, -8}
      right: {:ok, -7}
      

  * test top returns players sorted by total descending
      
      
      match (=) failed
      code:  assert [{"alice", 100}, {"bob", 80}, {"carol", 50}] = CumulativeLeaderboard.top(board, 3)
      left:  [{"alice", 100}, {"bob", 80}, {"carol", 50}]
      right: [{"alice", 101}, {"bob", 81}, {"carol", 51}]
      

  (…4 more)
```
