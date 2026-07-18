  test "non-atom step names work as context keys and in the error map" do
    saga =
      Saga.new()
      |> Saga.step("reserve", ok_action(:reserve, :held), comp(:reserve, {:ok, :released}))
      |> Saga.step({:charge, 1}, fail_action(:charge, :declined), comp(:charge))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.step == {:charge, 1}
    assert err.error == :declined
    assert err.compensated == ["reserve"]
    assert err.compensations == %{"reserve" => {:ok, :released}}
  end