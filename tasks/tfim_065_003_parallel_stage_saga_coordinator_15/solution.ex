  test "compensation walks every earlier stage most recent stage first" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, ok_action(:a, 1), comp(:a)},
        {:b, ok_action(:b, 2), comp(:b)}
      ])
      |> ParallelSaga.stage([
        {:c, ok_action(:c, 3), comp(:c)},
        {:d, ok_action(:d, 4), comp(:d)}
      ])
      |> ParallelSaga.stage([
        {:e, ok_action(:e, 5), comp(:e)},
        {:f, fail_action(:f, :nope), comp(:f)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.stage == 2
    assert err.compensated == [:e, :d, :c, :b, :a]

    assert Recorder.comps() ==
             [{:comp, :e}, {:comp, :d}, {:comp, :c}, {:comp, :b}, {:comp, :a}]
  end