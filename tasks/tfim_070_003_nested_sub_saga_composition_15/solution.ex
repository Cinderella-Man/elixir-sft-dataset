  test "recorded compensation exception carries the raised struct and a stacktrace" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> raise ArgumentError, "kaput" end)
      |> Saga.step(:b, fn _ -> {:error, :fail} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:error, [:b], :fail, comp} = result
    assert {:exception, exception, stack} = comp[:a]
    assert %ArgumentError{message: "kaput"} = exception
    assert is_list(stack)
    assert stack != []
    assert Enum.all?(stack, &is_tuple/1)
  end