defmodule LeaderboardTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Setup
  # -------------------------------------------------------

  setup do
    # Use a unique atom per test to avoid ETS table name collisions
    # when tests run concurrently.
    board_name = :"board_#{:erlang.unique_integer([:positive])}"
    {:ok, board} = Leaderboard.new(board_name)
    %{board: board}
  end

  # -------------------------------------------------------
  # Basic submit / top
  # -------------------------------------------------------

  test "top returns empty list when no scores submitted", %{board: board} do
    assert [] = Leaderboard.top(board, 5)
  end

  test "top returns players sorted by score descending", %{board: board} do
    Leaderboard.submit_score(board, "alice", 300)
    Leaderboard.submit_score(board, "bob", 100)
    Leaderboard.submit_score(board, "carol", 200)

    assert [{"alice", 300}, {"carol", 200}, {"bob", 100}] = Leaderboard.top(board, 3)
  end

  test "top(n) returns at most n players", %{board: board} do
    for i <- 1..10 do
      Leaderboard.submit_score(board, "player:#{i}", i * 10)
    end

    result = Leaderboard.top(board, 3)
    assert length(result) == 3

    # Should be the three highest scores
    [{_, s1}, {_, s2}, {_, s3}] = result
    assert s1 >= s2
    assert s2 >= s3
    assert s1 == 100
    assert s2 == 90
    assert s3 == 80
  end

  test "top returns all players when n exceeds player count", %{board: board} do
    Leaderboard.submit_score(board, "alice", 50)
    Leaderboard.submit_score(board, "bob", 80)

    result = Leaderboard.top(board, 100)
    assert length(result) == 2
  end

  # -------------------------------------------------------
  # Score overwrite rules
  # -------------------------------------------------------

  test "submitting a higher score updates the stored score", %{board: board} do
    Leaderboard.submit_score(board, "alice", 100)
    Leaderboard.submit_score(board, "alice", 250)

    assert [{"alice", 250}] = Leaderboard.top(board, 1)
  end

  test "submitting a lower score does not overwrite a higher one", %{board: board} do
    Leaderboard.submit_score(board, "alice", 500)
    Leaderboard.submit_score(board, "alice", 50)

    assert [{"alice", 500}] = Leaderboard.top(board, 1)
  end

  test "submitting the same score is a no-op and keeps the score", %{board: board} do
    Leaderboard.submit_score(board, "alice", 100)
    Leaderboard.submit_score(board, "alice", 100)

    assert [{"alice", 100}] = Leaderboard.top(board, 1)
  end

  test "multiple score updates converge to the personal best", %{board: board} do
    scores = [40, 90, 30, 75, 90, 10, 91, 88]
    for s <- scores, do: Leaderboard.submit_score(board, "alice", s)

    assert {:ok, _, 91} = Leaderboard.rank(board, "alice")
  end

  # -------------------------------------------------------
  # Rank
  # -------------------------------------------------------

  test "rank returns :error for unknown player", %{board: board} do
    assert {:error, :not_found} = Leaderboard.rank(board, "ghost")
  end

  test "rank returns 1-based position and score", %{board: board} do
    Leaderboard.submit_score(board, "alice", 300)
    Leaderboard.submit_score(board, "bob", 100)
    Leaderboard.submit_score(board, "carol", 200)

    assert {:ok, 1, 300} = Leaderboard.rank(board, "alice")
    assert {:ok, 2, 200} = Leaderboard.rank(board, "carol")
    assert {:ok, 3, 100} = Leaderboard.rank(board, "bob")
  end

  test "rank is 1 for the sole player", %{board: board} do
    Leaderboard.submit_score(board, "solo", 42)
    assert {:ok, 1, 42} = Leaderboard.rank(board, "solo")
  end

  test "rank updates after a higher score is submitted", %{board: board} do
    Leaderboard.submit_score(board, "alice", 50)
    Leaderboard.submit_score(board, "bob", 200)

    # alice is initially rank 2
    assert {:ok, 2, 50} = Leaderboard.rank(board, "alice")

    # alice submits a new high score that beats bob
    Leaderboard.submit_score(board, "alice", 999)
    assert {:ok, 1, 999} = Leaderboard.rank(board, "alice")
    assert {:ok, 2, 200} = Leaderboard.rank(board, "bob")
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "player IDs of different types are treated independently", %{board: board} do
    Leaderboard.submit_score(board, "1", 100)
    Leaderboard.submit_score(board, 1, 200)
    Leaderboard.submit_score(board, :one, 300)

    assert {:ok, 1, 300} = Leaderboard.rank(board, :one)
    assert {:ok, 2, 200} = Leaderboard.rank(board, 1)
    assert {:ok, 3, 100} = Leaderboard.rank(board, "1")
  end

  # -------------------------------------------------------
  # Multiple boards are isolated
  # -------------------------------------------------------

  test "two boards do not share state" do
    {:ok, board_a} = Leaderboard.new(:"board_a_#{:erlang.unique_integer([:positive])}")
    {:ok, board_b} = Leaderboard.new(:"board_b_#{:erlang.unique_integer([:positive])}")

    Leaderboard.submit_score(board_a, "alice", 999)

    assert {:error, :not_found} = Leaderboard.rank(board_b, "alice")
    assert [] = Leaderboard.top(board_b, 5)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "score of zero is valid", %{board: board} do
    assert :ok = Leaderboard.submit_score(board, "zerohero", 0)
    assert {:ok, 1, 0} = Leaderboard.rank(board, "zerohero")
  end

  test "negative scores are valid and ranked correctly", %{board: board} do
    Leaderboard.submit_score(board, "alice", -10)
    Leaderboard.submit_score(board, "bob", -50)
    Leaderboard.submit_score(board, "carol", 0)

    assert [{"carol", 0}, {"alice", -10}, {"bob", -50}] = Leaderboard.top(board, 3)
    assert {:ok, 1, 0} = Leaderboard.rank(board, "carol")
    assert {:ok, 3, -50} = Leaderboard.rank(board, "bob")
  end

  test "large number of players are ranked correctly", %{board: board} do
    for i <- 1..1_000 do
      Leaderboard.submit_score(board, "player:#{i}", i)
    end

    [{top_player, top_score} | _] = Leaderboard.top(board, 1)
    assert top_score == 1_000
    assert top_player == "player:1000"

    assert {:ok, 1, 1_000} = Leaderboard.rank(board, "player:1000")
    assert {:ok, 1_000, 1} = Leaderboard.rank(board, "player:1")
  end

  # -------------------------------------------------------
  # Cross-process access (the board is public)
  # -------------------------------------------------------

  test "a process other than the creator can submit scores", %{board: board} do
    # A :private or :protected table would make this write fail in the
    # non-owning process, so the write must be attempted from a foreign one.
    writer = Task.async(fn -> Leaderboard.submit_score(board, "remote_writer", 150) end)

    assert :ok = Task.await(writer, 5_000)
    assert {:ok, 1, 150} = Leaderboard.rank(board, "remote_writer")

    # The highest-score rule must also hold across process boundaries.
    lower = Task.async(fn -> Leaderboard.submit_score(board, "remote_writer", 20) end)
    assert :ok = Task.await(lower, 5_000)
    assert {:ok, 1, 150} = Leaderboard.rank(board, "remote_writer")
  end

  test "a process other than the creator can read top and rank", %{board: board} do
    Leaderboard.submit_score(board, "alice", 300)
    Leaderboard.submit_score(board, "bob", 100)

    reader =
      Task.async(fn ->
        {Leaderboard.top(board, 2), Leaderboard.rank(board, "bob"),
         Leaderboard.rank(board, "ghost")}
      end)

    assert {[{"alice", 300}, {"bob", 100}], {:ok, 2, 100}, {:error, :not_found}} =
             Task.await(reader, 5_000)
  end

  test "writes from a foreign process are visible to a third process", %{board: board} do
    writer = Task.async(fn -> Leaderboard.submit_score(board, "carol", 77) end)
    assert :ok = Task.await(writer, 5_000)

    reader = Task.async(fn -> Leaderboard.rank(board, "carol") end)
    assert {:ok, 1, 77} = Task.await(reader, 5_000)
  end

  # -------------------------------------------------------
  # Concurrent operations
  # -------------------------------------------------------

  test "concurrent submits from many processes all land on the board", %{board: board} do
    players = for i <- 1..50, do: "concurrent:#{i}"

    players
    |> Enum.map(fn player ->
      Task.async(fn -> Leaderboard.submit_score(board, player, 10) end)
    end)
    |> Enum.each(fn task -> assert :ok = Task.await(task, 10_000) end)

    assert length(Leaderboard.top(board, 100)) == 50

    for player <- players do
      assert {:ok, rank, 10} = Leaderboard.rank(board, player)
      assert is_integer(rank) and rank >= 1
    end
  end

  test "racing submits for one player still keep the all-time highest", %{board: board} do
    # Interleaved submissions of the same score set from several processes:
    # a lost update (read-then-write without atomicity) would leave a score
    # lower than the maximum ever submitted.
    players = ["racer_a", "racer_b", "racer_c"]
    scores = Enum.to_list(1..200)

    for player <- players, _writer <- 1..6 do
      Task.async(fn ->
        for score <- Enum.shuffle(scores) do
          Leaderboard.submit_score(board, player, score)
        end

        :done
      end)
    end
    |> Enum.each(fn task -> assert :done = Task.await(task, 60_000) end)

    for player <- players do
      assert {:ok, 1, 200} = Leaderboard.rank(board, player)
    end

    assert length(Leaderboard.top(board, 10)) == 3
  end
end
