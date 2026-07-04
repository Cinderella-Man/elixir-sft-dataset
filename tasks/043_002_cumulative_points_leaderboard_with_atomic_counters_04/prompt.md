Implement the public `top/2` function.

`top(board, n)` retrieves the top `n` players from the leaderboard, ranked by their
cumulative total in descending order. It returns a list of `{player_id, total}`
tuples. If fewer than `n` players exist, return all of them. Ties (players with the
same total) may be returned in any order.

Handle `n == 0` by returning an empty list `[]`. For a positive integer `n`, read
every row from the ETS table (e.g. with `:ets.tab2list/1`), sort the rows by score in
descending order, and take the first `n` entries. The rows are already stored as
`{player_id, total}` tuples, so no reshaping is needed. Do not mutate the table or use
a GenServer — this is a pure read over the ETS-backed store.

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
    new_total = :ets.update_counter(board, player_id, points, {player_id, 0})
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
  def top(board, n) do
    # TODO
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