  test "first step failing runs no compensations" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:error, :immediate} end, fn _ctx ->
        track(:comp, :a)
      end)
      |> Saga.execute(%{})

    assert {:error, :a, :immediate, []} = result
    assert tracked(:comp) == []
  end