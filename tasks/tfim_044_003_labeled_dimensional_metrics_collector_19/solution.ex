  test "increment raises for a negative amount in both call shapes" do
    assert_raise FunctionClauseError, fn ->
      Metrics.increment(:bytes, %{route: "/x"}, -1)
    end

    assert_raise FunctionClauseError, fn ->
      Metrics.increment(:bytes, -5)
    end

    assert Metrics.get(:bytes, %{route: "/x"}) == nil
    assert Metrics.get(:bytes) == nil
  end