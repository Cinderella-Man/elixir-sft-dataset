  test "first compensable step failing runs no compensations" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:error, :immediate} end, fn _ -> track(:comp, :a) end)
      |> Saga.execute(%{})

    assert {:error, :a, :immediate, []} = result
    assert tracked(:comp) == []
  end