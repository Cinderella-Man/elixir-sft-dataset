  test "invalid acquire neither drains an existing bucket nor creates a new one", %{sp: sp} do
    # Establish a known drained state on an existing bucket.
    assert {:ok, 4, 9} = SharedPoolBucket.acquire(sp, "alice", 5, 1.0)

    # Invalid tokens raises and must not touch any existing state.
    assert_raise FunctionClauseError, fn ->
      SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 0)
    end

    # Existing bucket untouched (still 4, not drained further); global untouched.
    assert {:ok, 4} = SharedPoolBucket.key_level(sp, "alice", 5, 1.0)
    assert {:ok, 9} = SharedPoolBucket.global_level(sp)

    # A never-seen bucket targeted by an invalid call must not be created: a later
    # query with a different capacity still reports a fresh, full bucket.
    assert_raise FunctionClauseError, fn ->
      SharedPoolBucket.acquire(sp, "ghost", 0, 1.0, 1)
    end

    assert {:ok, 100} = SharedPoolBucket.key_level(sp, "ghost", 100, 1.0)
  end