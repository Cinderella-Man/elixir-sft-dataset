# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule CumulativeLeaderboardTest do
  use ExUnit.Case, async: false

  setup do
    board_name = :"cboard_#{:erlang.unique_integer([:positive])}"
    {:ok, board} = CumulativeLeaderboard.new(board_name)
    %{board: board}
  end

  test "total is :error for unknown player", %{board: board} do
    assert {:error, :not_found} = CumulativeLeaderboard.total(board, "ghost")
  end

  test "first award initializes from zero", %{board: board} do
    assert {:ok, 10} = CumulativeLeaderboard.add_points(board, "alice", 10)
    assert {:ok, 10} = CumulativeLeaderboard.total(board, "alice")
  end

  test "points accumulate across awards", %{board: board} do
    assert {:ok, 10} = CumulativeLeaderboard.add_points(board, "alice", 10)
    assert {:ok, 15} = CumulativeLeaderboard.add_points(board, "alice", 5)
    assert {:ok, 12} = CumulativeLeaderboard.add_points(board, "alice", -3)
    assert {:ok, 12} = CumulativeLeaderboard.total(board, "alice")
  end

  test "negative running totals are valid", %{board: board} do
    assert {:ok, -8} = CumulativeLeaderboard.add_points(board, "alice", -8)
    assert {:ok, 1, -8} = CumulativeLeaderboard.rank(board, "alice")
  end

  test "top returns empty list when no scores", %{board: board} do
    # TODO
  end

  test "top returns players sorted by total descending", %{board: board} do
    CumulativeLeaderboard.add_points(board, "alice", 100)
    CumulativeLeaderboard.add_points(board, "bob", 40)
    CumulativeLeaderboard.add_points(board, "bob", 40)
    CumulativeLeaderboard.add_points(board, "carol", 50)

    assert [{"alice", 100}, {"bob", 80}, {"carol", 50}] = CumulativeLeaderboard.top(board, 3)
  end

  test "top(n) returns at most n players", %{board: board} do
    for i <- 1..10, do: CumulativeLeaderboard.add_points(board, "p:#{i}", i * 10)
    assert length(CumulativeLeaderboard.top(board, 3)) == 3
  end

  test "rank is 1-based competition ranking with shared ranks on ties", %{board: board} do
    CumulativeLeaderboard.add_points(board, "alice", 300)
    CumulativeLeaderboard.add_points(board, "bob", 300)
    CumulativeLeaderboard.add_points(board, "carol", 100)

    assert {:ok, 1, 300} = CumulativeLeaderboard.rank(board, "alice")
    assert {:ok, 1, 300} = CumulativeLeaderboard.rank(board, "bob")
    # two players tied at rank 1 -> next player is rank 3
    assert {:ok, 3, 100} = CumulativeLeaderboard.rank(board, "carol")
  end

  test "rank returns :error for unknown player", %{board: board} do
    assert {:error, :not_found} = CumulativeLeaderboard.rank(board, "ghost")
  end

  test "different player id types are independent", %{board: board} do
    CumulativeLeaderboard.add_points(board, "1", 100)
    CumulativeLeaderboard.add_points(board, 1, 200)
    CumulativeLeaderboard.add_points(board, :one, 300)

    assert {:ok, 300} = CumulativeLeaderboard.total(board, :one)
    assert {:ok, 200} = CumulativeLeaderboard.total(board, 1)
    assert {:ok, 100} = CumulativeLeaderboard.total(board, "1")
  end

  test "two boards do not share state" do
    {:ok, a} = CumulativeLeaderboard.new(:"cba_#{:erlang.unique_integer([:positive])}")
    {:ok, b} = CumulativeLeaderboard.new(:"cbb_#{:erlang.unique_integer([:positive])}")
    CumulativeLeaderboard.add_points(a, "alice", 5)
    assert {:error, :not_found} = CumulativeLeaderboard.total(b, "alice")
  end

  test "concurrent awards to the same player are not lost", %{board: board} do
    1..100
    |> Enum.map(fn _ -> Task.async(fn -> CumulativeLeaderboard.add_points(board, "p", 1) end) end)
    |> Enum.each(&Task.await/1)

    assert {:ok, 100} = CumulativeLeaderboard.total(board, "p")
  end

  test "concurrent awards across many players are all correct", %{board: board} do
    for p <- 1..20 do
      1..50
      |> Enum.map(fn _ -> Task.async(fn -> CumulativeLeaderboard.add_points(board, p, 2) end) end)
      |> Enum.each(&Task.await/1)
    end

    for p <- 1..20 do
      assert {:ok, 100} = CumulativeLeaderboard.total(board, p)
    end
  end

  test "top returns every player when n exceeds the player count", %{board: board} do
    CumulativeLeaderboard.add_points(board, "alice", 30)
    CumulativeLeaderboard.add_points(board, "bob", 10)

    assert [{"alice", 30}, {"bob", 10}] == CumulativeLeaderboard.top(board, 25)
  end

  test "add_points refuses non-integer point values", %{board: board} do
    assert_raise FunctionClauseError, fn ->
      CumulativeLeaderboard.add_points(board, "alice", 1.5)
    end

    assert_raise FunctionClauseError, fn ->
      CumulativeLeaderboard.add_points(board, "alice", "5")
    end

    assert {:error, :not_found} = CumulativeLeaderboard.total(board, "alice")
  end

  test "a zero-point award registers the player with a total of zero", %{board: board} do
    assert {:ok, 0} = CumulativeLeaderboard.add_points(board, "alice", 0)
    assert {:ok, 0} = CumulativeLeaderboard.total(board, "alice")
    assert {:ok, 1, 0} = CumulativeLeaderboard.rank(board, "alice")
  end

  test "top sorts negative totals below zero and positive totals", %{board: board} do
    CumulativeLeaderboard.add_points(board, "alice", -50)
    CumulativeLeaderboard.add_points(board, "bob", 0)
    CumulativeLeaderboard.add_points(board, "carol", 5)
    CumulativeLeaderboard.add_points(board, "carol", -20)

    assert [{"bob", 0}, {"carol", -15}, {"alice", -50}] == CumulativeLeaderboard.top(board, 3)
  end
end
```
