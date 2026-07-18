  test "a failing stage aborts the saga so later stages never run" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, fail_action(:a, :boom), comp(:a)}])
      |> ParallelSaga.stage([{:b, ok_action(:b, 2), comp(:b)}])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.stage == 0
    assert err.failed == %{a: :boom}
    assert Recorder.action_names() == MapSet.new([:a])
    assert Recorder.comps() == []
  end