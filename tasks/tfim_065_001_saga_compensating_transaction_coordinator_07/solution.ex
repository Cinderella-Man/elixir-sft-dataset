  test "a compensation sees its own step's stored result in the context" do
    reserve = fn _ctx -> {:ok, %{reservation_id: "abc"}} end

    cancel = fn ctx ->
      Recorder.record({:comp_ctx, ctx[:reserve]})
      {:ok, :cancelled}
    end

    saga =
      Saga.new()
      |> Saga.step(:reserve, reserve, cancel)
      |> Saga.step(:charge, fail_action(:charge, :declined), comp(:charge))

    assert {:error, _} = Saga.execute(saga, %{})

    assert {:comp_ctx, %{reservation_id: "abc"}} in Recorder.events()
  end