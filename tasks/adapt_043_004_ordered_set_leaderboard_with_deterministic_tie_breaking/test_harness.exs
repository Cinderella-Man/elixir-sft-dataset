defmodule OrderedLeaderboardTest do
  use ExUnit.Case, async: false

  setup do
    name = :"oboard_#{:erlang.unique_integer([:positive])}"
    {:ok, board} = OrderedLeaderboard.new(name)
    %{board: board}
  end

  test "top is empty with no scores", %{board: board} do
    assert [] = OrderedLeaderboard.top(board, 5)
  end

  test "top is sorted by score descending", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 300)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 200)

    assert [{"alice", 300}, {"carol", 200}, {"bob", 100}] = OrderedLeaderboard.top(board, 3)
  end

  test "top(n) caps results and picks the highest", %{board: board} do
    for i <- 1..10, do: OrderedLeaderboard.submit_score(board, "p:#{i}", i * 10)
    assert [{"p:10", 100}, {"p:9", 90}, {"p:8", 80}] = OrderedLeaderboard.top(board, 3)
  end

  test "higher score overwrites, lower is a no-op", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "alice", 250)
    OrderedLeaderboard.submit_score(board, "alice", 50)
    assert [{"alice", 250}] = OrderedLeaderboard.top(board, 1)
    assert {:ok, 1, 250} = OrderedLeaderboard.rank(board, "alice")
  end

  test "ties broken by who reached the score first", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 100)

    assert [{"alice", 100}, {"bob", 100}, {"carol", 100}] = OrderedLeaderboard.top(board, 3)
  end

  test "ranks are unique ordinals even on ties", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 50)

    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100} = OrderedLeaderboard.rank(board, "bob")
    assert {:ok, 3, 50} = OrderedLeaderboard.rank(board, "carol")
  end

  test "reaching a new high re-timestamps arrival for tie-breaking", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    # alice and bob tied at 100, alice first -> alice ahead
    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)

    # bob jumps ahead, then both settle at 200 with bob reaching it first
    OrderedLeaderboard.submit_score(board, "bob", 200)
    OrderedLeaderboard.submit_score(board, "alice", 200)
    assert [{"bob", 200}, {"alice", 200}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 200} = OrderedLeaderboard.rank(board, "bob")
    assert {:ok, 2, 200} = OrderedLeaderboard.rank(board, "alice")
  end

  test "rank is :not_found for unknown player", %{board: board} do
    assert {:error, :not_found} = OrderedLeaderboard.rank(board, "ghost")
  end

  test "rank 1 for sole player", %{board: board} do
    OrderedLeaderboard.submit_score(board, "solo", 42)
    assert {:ok, 1, 42} = OrderedLeaderboard.rank(board, "solo")
  end

  test "zero and negative scores rank correctly", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", -10)
    OrderedLeaderboard.submit_score(board, "bob", -50)
    OrderedLeaderboard.submit_score(board, "carol", 0)

    assert [{"carol", 0}, {"alice", -10}, {"bob", -50}] = OrderedLeaderboard.top(board, 3)
    assert {:ok, 1, 0} = OrderedLeaderboard.rank(board, "carol")
    assert {:ok, 3, -50} = OrderedLeaderboard.rank(board, "bob")
  end

  test "different id types are independent", %{board: board} do
    OrderedLeaderboard.submit_score(board, "1", 100)
    OrderedLeaderboard.submit_score(board, 1, 200)
    OrderedLeaderboard.submit_score(board, :one, 300)

    assert {:ok, 1, 300} = OrderedLeaderboard.rank(board, :one)
    assert {:ok, 2, 200} = OrderedLeaderboard.rank(board, 1)
    assert {:ok, 3, 100} = OrderedLeaderboard.rank(board, "1")
  end

  test "two boards do not share state" do
    {:ok, a} = OrderedLeaderboard.new(:"oba_#{:erlang.unique_integer([:positive])}")
    {:ok, b} = OrderedLeaderboard.new(:"obb_#{:erlang.unique_integer([:positive])}")
    OrderedLeaderboard.submit_score(a, "alice", 999)
    assert {:error, :not_found} = OrderedLeaderboard.rank(b, "alice")
    assert [] = OrderedLeaderboard.top(b, 5)
  end

  test "large number of players ranked correctly", %{board: board} do
    for i <- 1..1_000, do: OrderedLeaderboard.submit_score(board, "player:#{i}", i)
    assert [{"player:1000", 1_000}] = OrderedLeaderboard.top(board, 1)
    assert {:ok, 1, 1_000} = OrderedLeaderboard.rank(board, "player:1000")
    assert {:ok, 1_000, 1} = OrderedLeaderboard.rank(board, "player:1")
  end

  test "resubmitting the exact same score does not re-timestamp arrival", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)

    # equal is not "strictly higher", so alice must keep her earlier arrival slot
    OrderedLeaderboard.submit_score(board, "alice", 100)

    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100} = OrderedLeaderboard.rank(board, "bob")
  end

  test "float and integer scores of equal value tie and break by arrival", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100.0)

    assert [{"alice", 100}, {"bob", 100.0}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100.0} = OrderedLeaderboard.rank(board, "bob")

    # 100.0 is not strictly higher than 100, so it must not move alice
    OrderedLeaderboard.submit_score(board, "alice", 100.0)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")

    OrderedLeaderboard.submit_score(board, "alice", 100.5)
    assert [{"alice", 100.5}, {"bob", 100.0}] = OrderedLeaderboard.top(board, 2)
  end

  test "top returns every player when n exceeds the population", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 30)
    OrderedLeaderboard.submit_score(board, "bob", 20)

    assert [{"alice", 30}, {"bob", 20}] = OrderedLeaderboard.top(board, 50)
    assert [{"alice", 30}] = OrderedLeaderboard.top(board, 1)
  end
end
