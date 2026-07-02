  test "failure with all compensations succeeding: no abort" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b))
      |> PolicySaga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.step == :c
    assert err.error == :boom
    assert err.compensated == [:b, :a]
    assert err.aborted_at == nil
    assert err.uncompensated == []
    assert Recorder.comps() == [{:comp, :b}, {:comp, :a}]
  end