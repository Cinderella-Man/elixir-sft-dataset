  test "multiple failures in a stage are all reported" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, fail_action(:a, :e1), comp(:a)},
        {:b, fail_action(:b, :e2), comp(:b)},
        {:c, ok_action(:c, 3), comp(:c)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.stage == 0
    assert err.failed == %{a: :e1, b: :e2}
    # only the succeeded step is compensated; no earlier stages exist.
    assert err.compensated == [:c]
  end