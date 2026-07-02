  test "happy path: all stages succeed and results merge" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, ok_action(:a, 1), comp(:a)},
        {:b, ok_action(:b, 2), comp(:b)}
      ])
      |> ParallelSaga.stage([{:c, ok_action(:c, 3), comp(:c)}])

    assert {:ok, ctx} = ParallelSaga.execute(saga, %{order_id: 7})
    assert ctx.order_id == 7
    assert ctx.a == 1 and ctx.b == 2 and ctx.c == 3

    assert Recorder.action_names() == MapSet.new([:a, :b, :c])
    assert Recorder.comps() == []
  end