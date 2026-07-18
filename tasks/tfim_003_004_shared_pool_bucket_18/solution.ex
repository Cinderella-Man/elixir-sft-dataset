  test "non-positive capacity, rate or tokens match no clause; capacity 1 is legal", %{sp: sp} do
    assert {:ok, 0, _} = SharedPoolBucket.acquire(sp, "v1", 1, 1.0, 1)
    assert {:ok, _} = SharedPoolBucket.key_level(sp, "v1", 1, 1.0)

    assert_raise FunctionClauseError, fn -> SharedPoolBucket.acquire(sp, "v2", 0, 1.0, 1) end
    assert_raise FunctionClauseError, fn -> SharedPoolBucket.acquire(sp, "v2", 1, 0.0, 1) end
    assert_raise FunctionClauseError, fn -> SharedPoolBucket.acquire(sp, "v2", 1, 1.0, 0) end
    assert_raise FunctionClauseError, fn -> SharedPoolBucket.key_level(sp, "v2", 0, 1.0) end
  end