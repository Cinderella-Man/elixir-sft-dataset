  test "a compensation sees its own step's stored result" do
    reserve = fn _ -> {:ok, %{reservation_id: "abc"}} end

    cancel = fn ctx ->
      Recorder.record({:comp_ctx, ctx[:reserve]})
      {:ok, :cancelled}
    end

    saga =
      PolicySaga.new()
      |> PolicySaga.step(:reserve, reserve, cancel)
      |> PolicySaga.step(:charge, fail_action(:charge, :declined), comp(:charge))

    assert {:error, _} = PolicySaga.execute(saga, %{})
    assert {:comp_ctx, %{reservation_id: "abc"}} in Recorder.events()
  end