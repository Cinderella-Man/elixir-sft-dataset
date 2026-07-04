Implement the public `rank/2` function. Given a `board` and a `player_id`, look up
the player in the ETS table. If the lookup returns no row, return `{:error, :not_found}`.
Otherwise, the player exists with some `score`; compute the player's 1-based rank using
standard competition ("1224") ranking, where tied players share the same rank. Do this by
counting how many players have a strictly greater total than `score` — use an `:ets.select_count/2`
match spec of the form `[{{:_, :"$1"}, [{:>, :"$1", score}], [true]}]` so the count happens at the
ETS level rather than by materializing the whole table. The player's rank is that count plus one.
Return `{:ok, rank, total}` where `total` is the player's own `score`.

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
    # TODO
  end
end
```