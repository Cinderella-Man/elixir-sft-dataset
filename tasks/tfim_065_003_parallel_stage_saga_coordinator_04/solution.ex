  test "a later stage sees an earlier stage's results" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, ok_action(:a, 10), comp(:a)}])
      |> ParallelSaga.stage([{:b, fn ctx -> {:ok, ctx.a + 5} end, comp(:b)}])

    assert {:ok, %{a: 10, b: 15}} = ParallelSaga.execute(saga, %{})
  end