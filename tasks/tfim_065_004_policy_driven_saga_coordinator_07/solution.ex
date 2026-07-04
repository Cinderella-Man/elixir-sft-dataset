  test "first step failing runs no compensations" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, fail_action(:a, :boom), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.step == :a
    assert err.compensated == []
    assert err.compensations == %{}
    assert err.aborted_at == nil
    assert err.uncompensated == []
    assert Recorder.comps() == []
  end