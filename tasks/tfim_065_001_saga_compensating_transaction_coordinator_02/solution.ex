  test "runs all steps and merges results into the context" do
    saga =
      Saga.new()
      |> Saga.step(:reserve, ok_action(:reserve, %{id: "r1"}), comp(:reserve))
      |> Saga.step(:charge, ok_action(:charge, %{txn: "t1"}), comp(:charge))
      |> Saga.step(:ship, ok_action(:ship, :shipped), comp(:ship))

    assert {:ok, ctx} = Saga.execute(saga, %{order_id: 42})

    assert ctx.order_id == 42
    assert ctx.reserve == %{id: "r1"}
    assert ctx.charge == %{txn: "t1"}
    assert ctx.ship == :shipped

    # No compensations should have run
    assert Recorder.events() == [
             {:action, :reserve},
             {:action, :charge},
             {:action, :ship}
           ]
  end