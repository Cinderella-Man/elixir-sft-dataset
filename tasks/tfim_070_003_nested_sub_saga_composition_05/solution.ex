  test "deeply nested sagas propagate the full failure path" do
    inner =
      Saga.new()
      |> Saga.step(:deep, fn _ -> {:error, :deep_fail} end, fn _ -> :ud end)

    middle =
      Saga.new()
      |> Saga.nest(:inner, inner)

    result =
      Saga.new()
      |> Saga.nest(:middle, middle)
      |> Saga.execute(%{})

    assert {:error, [:middle, :inner, :deep], :deep_fail, comp} = result
    # nothing completed anywhere, so nested compensation lists are empty
    assert comp == [middle: [inner: []]]
  end