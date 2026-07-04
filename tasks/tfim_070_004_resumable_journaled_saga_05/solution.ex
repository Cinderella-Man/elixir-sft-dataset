  test "resume compensates journaled and newly run steps in reverse on failure" do
    saga =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)
      |> Saga.step(:c, fn _ -> {:error, :late} end, fn _ -> :uc end)

    journal = [{:completed, :a, 1}]
    result = Saga.resume(saga, %{}, journal)

    assert {:error, :c, :late, comp, jr} = result
    assert comp == [b: :ub, a: :ua]

    assert jr == [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:failed, :c, :late},
             {:compensated, :b, :ub},
             {:compensated, :a, :ua}
           ]
  end