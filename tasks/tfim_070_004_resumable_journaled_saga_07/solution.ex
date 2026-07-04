  test "resume merges journaled results into the context for later steps" do
    saga =
      Saga.new()
      |> Saga.step(:base, fn _ -> {:ok, 10} end, fn _ -> nil end)
      |> Saga.step(:derived, fn ctx -> {:ok, ctx.base * 3} end, fn _ -> nil end)

    result = Saga.resume(saga, %{}, [{:completed, :base, 10}])
    assert {:ok, ctx, _jr} = result
    assert ctx.derived == 30
  end