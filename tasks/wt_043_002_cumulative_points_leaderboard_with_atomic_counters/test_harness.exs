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
    assert [] = CumulativeLeaderboard.top(board, 5)
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
end