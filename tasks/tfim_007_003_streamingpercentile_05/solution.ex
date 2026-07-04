  test "push rejects non-numeric values and non-positive window sizes", %{sp: s} do
    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", :not_number, 10)
    end

    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", 10, 0)
    end

    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", 10, -1)
    end
  end