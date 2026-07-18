  test "failing nest reports inner results first then completed outer nest and leaf" do
    first =
      Saga.new()
      |> Saga.step(:p, fn _ -> {:ok, 1} end, fn _ -> :up end)
      |> Saga.step(:q, fn _ -> {:ok, 2} end, fn _ -> :uq end)

    second =
      Saga.new()
      |> Saga.step(:r, fn _ -> {:ok, 3} end, fn _ -> :ur end)
      |> Saga.step(:s, fn _ -> {:error, :sfail} end, fn _ -> :us end)

    result =
      Saga.new()
      |> Saga.step(:top, fn _ -> {:ok, :t} end, fn _ -> :utop end)
      |> Saga.nest(:one, first)
      |> Saga.nest(:two, second)
      |> Saga.execute(%{})

    assert {:error, [:two, :s], :sfail, comp} = result
    assert comp == [two: [r: :ur], one: [q: :uq, p: :up], top: :utop]
  end