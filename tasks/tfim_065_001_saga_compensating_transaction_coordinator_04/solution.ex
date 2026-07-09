  test "step 2 of 3 fails: step 1 is compensated, step 3 never runs" do
    saga =
      Saga.new()
      |> Saga.step(:reserve, ok_action(:reserve, %{id: "r1"}), comp(:reserve, {:ok, :cancelled}))
      |> Saga.step(:charge, fail_action(:charge, :card_declined), comp(:charge))
      |> Saga.step(:ship, ok_action(:ship, :shipped), comp(:ship))

    assert {:error, err} = Saga.execute(saga, %{user_id: 1})

    assert err.step == :charge
    assert err.error == :card_declined
    assert err.compensated == [:reserve]
    assert err.compensations == %{reserve: {:ok, :cancelled}}

    # reserve action ran, charge action ran (and failed), ship never ran,
    # only reserve was compensated, charge was NOT compensated.
    events = Recorder.events()

    assert events == [
             {:action, :reserve},
             {:action, :charge},
             {:comp, :reserve}
           ]
  end