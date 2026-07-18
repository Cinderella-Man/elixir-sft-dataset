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