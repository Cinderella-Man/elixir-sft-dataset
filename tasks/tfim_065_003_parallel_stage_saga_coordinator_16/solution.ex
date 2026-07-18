  test "an earlier compensation sees the failing stage's succeeded results" do
    spy = fn ctx ->
      Recorder.record({:comp_ctx, Map.take(ctx, [:a, :b, :c])})
      {:ok, :undone}
    end

    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, ok_action(:a, 1), spy}])
      |> ParallelSaga.stage([
        {:b, ok_action(:b, 2), comp(:b)},
        {:c, fail_action(:c, :boom), comp(:c)}
      ])

    assert {:error, _err} = ParallelSaga.execute(saga, %{})
    assert {:comp_ctx, %{a: 1, b: 2}} in Recorder.events()
  end