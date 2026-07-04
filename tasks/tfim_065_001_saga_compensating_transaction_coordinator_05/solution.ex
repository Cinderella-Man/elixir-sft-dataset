  test "first step failing runs no compensations" do
    saga =
      Saga.new()
      |> Saga.step(:reserve, fail_action(:reserve, :boom), comp(:reserve))
      |> Saga.step(:charge, ok_action(:charge, :ok), comp(:charge))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.step == :reserve
    assert err.error == :boom
    assert err.compensated == []
    assert err.compensations == %{}

    assert Recorder.events() == [{:action, :reserve}]
  end