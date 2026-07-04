  test "a failing compensation is recorded but the others still run" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a, {:ok, :undo_a}))
      |> RetrySaga.step(:b, flaky_action(:b, 0, 2), comp(:b, {:error, :undo_failed}))
      |> RetrySaga.step(:c, always_fail(:c, :nope), comp(:c))

    assert {:error, err} = RetrySaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}
  end