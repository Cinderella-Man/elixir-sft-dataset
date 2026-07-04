  test "a compensation sees its own step's stored result" do
    reserve = fn _ -> {:ok, %{reservation_id: "abc"}} end

    cancel = fn ctx ->
      Recorder.record({:comp_ctx, ctx[:reserve]})
      {:ok, :cancelled}
    end

    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:reserve, reserve, cancel}])
      |> ParallelSaga.stage([{:charge, fail_action(:charge, :declined), comp(:charge)}])

    assert {:error, _} = ParallelSaga.execute(saga, %{})
    assert {:comp_ctx, %{reservation_id: "abc"}} in Recorder.events()
  end