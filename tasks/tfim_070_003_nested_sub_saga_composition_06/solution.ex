  test "top-level leaf failure yields a single-element path" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:error, :nope} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:error, [:b], :nope, [a: :ua]} = result
  end