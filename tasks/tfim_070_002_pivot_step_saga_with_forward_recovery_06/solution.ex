  test "compensable failure rolls back prior compensable steps in reverse" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ca end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :cb end)
      |> Saga.step(:c, fn _ -> {:error, :boom} end, fn _ -> :cc end)
      |> Saga.execute(%{})

    assert {:error, :c, :boom, [b: :cb, a: :ca]} = result
  end