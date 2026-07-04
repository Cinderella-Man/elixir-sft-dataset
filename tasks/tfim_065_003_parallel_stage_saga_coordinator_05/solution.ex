  test "a failing step compensates its succeeded sibling and earlier stages" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, ok_action(:a, 1), comp(:a)},
        {:b, ok_action(:b, 2), comp(:b)}
      ])
      |> ParallelSaga.stage([
        {:c, fail_action(:c, :boom), comp(:c)},
        {:d, ok_action(:d, 4), comp(:d)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})

    assert err.stage == 1
    assert err.failed == %{c: :boom}
    # succeeded sibling first, then earlier stage in reverse declared order.
    assert err.compensated == [:d, :b, :a]
    assert Map.keys(err.compensations) |> Enum.sort() == [:a, :b, :d]
    # the failed step is never compensated.
    refute {:comp, :c} in Recorder.events()
    assert Recorder.comps() == [{:comp, :d}, {:comp, :b}, {:comp, :a}]
  end