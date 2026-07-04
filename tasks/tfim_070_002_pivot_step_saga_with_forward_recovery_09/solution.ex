  test "all compensations run even if one raises" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, :ok} end, fn _ ->
        track(:ran, :a)
        raise "boom in compensation a"
      end)
      |> Saga.step(:b, fn _ -> {:ok, :ok} end, fn _ -> track(:ran, :b) end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> track(:ran, :c) end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, _} = result
    assert :a in tracked(:ran)
    assert :b in tracked(:ran)
    refute :c in tracked(:ran)
  end