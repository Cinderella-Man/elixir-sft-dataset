  test "steps in the same stage do not see each other's results" do
    a = fn ctx -> {:ok, Map.has_key?(ctx, :b)} end
    b = fn ctx -> {:ok, Map.has_key?(ctx, :a)} end

    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, a, comp(:a)}, {:b, b, comp(:b)}])

    assert {:ok, ctx} = ParallelSaga.execute(saga, %{})
    assert ctx.a == false
    assert ctx.b == false
  end