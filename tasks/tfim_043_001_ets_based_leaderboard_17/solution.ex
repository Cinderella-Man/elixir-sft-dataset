  test "match-spec-significant atoms work as ordinary player ids", %{board: board} do
    # :_ and :"$1" carry special meaning inside ETS match-specifications
    # (wildcard and binding variable). As player ids they are ordinary terms
    # and must match only themselves — including on the overwrite path, which
    # runs after a key already exists.
    assert :ok = Leaderboard.submit_score(board, :_, 100)
    assert :ok = Leaderboard.submit_score(board, :"$1", 200)

    assert {:ok, _, 100} = Leaderboard.rank(board, :_)
    assert {:ok, _, 200} = Leaderboard.rank(board, :"$1")

    # A strictly higher score exercises the update path for such an id.
    assert :ok = Leaderboard.submit_score(board, :_, 500)
    assert {:ok, 1, 500} = Leaderboard.rank(board, :_)

    # A lower score is still a no-op for such an id, leaving the best intact,
    # and must not disturb the unrelated :_ entry.
    assert :ok = Leaderboard.submit_score(board, :"$1", 10)
    assert {:ok, _, 200} = Leaderboard.rank(board, :"$1")
    assert {:ok, 1, 500} = Leaderboard.rank(board, :_)
  end