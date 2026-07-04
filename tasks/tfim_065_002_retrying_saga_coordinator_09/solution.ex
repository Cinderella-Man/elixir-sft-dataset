  test "a compensation sees its own step's stored result" do
    reserve = fn _ -> {:ok, %{reservation_id: "abc"}} end

    cancel = fn ctx ->
      Recorder.record({:comp_ctx, ctx[:reserve]})
      {:ok, :cancelled}
    end

    saga =
      RetrySaga.new()
      |> RetrySaga.step(:reserve, reserve, cancel)
      |> RetrySaga.step(:charge, always_fail(:charge, :declined), comp(:charge))

    assert {:error, _} = RetrySaga.execute(saga, %{})
    assert {:comp_ctx, %{reservation_id: "abc"}} in Recorder.events()
  end