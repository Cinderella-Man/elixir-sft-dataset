  test "execute failure journal records completed, failed and compensated events" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:error, :boom} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:error, :b, :boom, comp, journal} = result
    assert comp == [a: :ua]

    assert journal == [
             {:completed, :a, 1},
             {:failed, :b, :boom},
             {:compensated, :a, :ua}
           ]
  end