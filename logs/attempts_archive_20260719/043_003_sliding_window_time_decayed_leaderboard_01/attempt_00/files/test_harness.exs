defmodule SlidingWindowLeaderboardTest do
  use ExUnit.Case, async: false

  setup do
    name = :"swboard_#{:erlang.unique_integer([:positive])}"
    {:ok, board} = SlidingWindowLeaderboard.new(name, 1000)
    %{board: board}
  end

  test "score is :not_found for unknown player", %{board: board} do
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "ghost", 10_000)
  end

  test "active events sum within the window", %{board: board} do
    :ok = SlidingWindowLeaderboard.record(board, "alice", 5, 10_000)
    :ok = SlidingWindowLeaderboard.record(board, "alice", 7, 10_200)
    assert {:ok, 12} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
  end

  test "expired events fall out of the window", %{board: board} do
    # window 1000, query at 10_500 -> cutoff 9_500
    SlidingWindowLeaderboard.record(board, "alice", 100, 9_000)
    SlidingWindowLeaderboard.record(board, "alice", 3, 10_000)
    assert {:ok, 3} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
  end

  test "player with only expired events is :not_found", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 100, 1_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
  end

  test "event exactly at the cutoff is expired", %{board: board} do
    # query at 10_000, window 1000 -> cutoff 9_000; event at 9_000 is expired
    SlidingWindowLeaderboard.record(board, "alice", 42, 9_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_000)

    # one millisecond later it is active
    SlidingWindowLeaderboard.record(board, "bob", 42, 9_001)
    assert {:ok, 42} = SlidingWindowLeaderboard.score(board, "bob", 10_000)
  end

  test "top excludes expired players and sorts descending", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 30, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 50, 10_100)
    SlidingWindowLeaderboard.record(board, "carol", 999, 1_000)

    assert [{"bob", 50}, {"alice", 30}] = SlidingWindowLeaderboard.top(board, 5, 10_500)
  end

  test "top(n) caps the result", %{board: board} do
    for i <- 1..6, do: SlidingWindowLeaderboard.record(board, "p:#{i}", i, 10_000)
    assert length(SlidingWindowLeaderboard.top(board, 3, 10_500)) == 3
  end

  test "rank uses competition ranking over active scores", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 50, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 50, 10_000)
    SlidingWindowLeaderboard.record(board, "carol", 10, 10_000)

    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "alice", 10_500)
    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "bob", 10_500)
    assert {:ok, 3, 10} = SlidingWindowLeaderboard.rank(board, "carol", 10_500)
  end

  test "rank is :not_found when the player has no active events", %{board: board} do
    assert {:error, :not_found} = SlidingWindowLeaderboard.rank(board, "ghost", 10_500)
  end

  test "prune deletes expired events and returns the count", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 1, 1_000)
    SlidingWindowLeaderboard.record(board, "alice", 2, 2_000)
    SlidingWindowLeaderboard.record(board, "bob", 3, 10_000)

    # at now = 10_500 cutoff = 9_500, both of alice's events expired
    assert 2 = SlidingWindowLeaderboard.prune(board, 10_500)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
    assert {:ok, 3} = SlidingWindowLeaderboard.score(board, "bob", 10_500)
  end

  test "score reflects the window sliding forward over time", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 10, 10_000)
    SlidingWindowLeaderboard.record(board, "alice", 20, 10_800)

    assert {:ok, 30} = SlidingWindowLeaderboard.score(board, "alice", 10_900)
    # advance so the first event (10_000) has expired: cutoff at 11_100 = 10_100
    assert {:ok, 20} = SlidingWindowLeaderboard.score(board, "alice", 11_100)
  end

  test "concurrent record calls are not lost", %{board: board} do
    1..100
    |> Enum.map(fn _ ->
      Task.async(fn -> SlidingWindowLeaderboard.record(board, "p", 1, 10_000) end)
    end)
    |> Enum.each(&Task.await/1)

    assert {:ok, 100} = SlidingWindowLeaderboard.score(board, "p", 10_500)
  end

  test "two boards do not share state" do
    {:ok, a} = SlidingWindowLeaderboard.new(:"swa_#{:erlang.unique_integer([:positive])}", 1000)
    {:ok, b} = SlidingWindowLeaderboard.new(:"swb_#{:erlang.unique_integer([:positive])}", 1000)
    SlidingWindowLeaderboard.record(a, "alice", 5, 10_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(b, "alice", 10_000)
  end
end