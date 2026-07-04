  test "within-stage compensation runs in reverse declared order" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:c, ok_action(:c, 1), comp(:c)},
        {:d, ok_action(:d, 2), comp(:d)},
        {:e, fail_action(:e, :fail), comp(:e)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.compensated == [:d, :c]
    assert Recorder.comps() == [{:comp, :d}, {:comp, :c}]
  end