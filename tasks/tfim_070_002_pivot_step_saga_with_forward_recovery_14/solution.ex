  test "retriable rejects a non-positive max_attempts via its guard" do
    saga = Saga.new()

    assert_raise FunctionClauseError, fn ->
      Saga.retriable(saga, :commit, fn _ -> {:ok, :x} end, 0)
    end

    assert_raise FunctionClauseError, fn ->
      Saga.retriable(saga, :commit, fn _ -> {:ok, :x} end, -1)
    end
  end