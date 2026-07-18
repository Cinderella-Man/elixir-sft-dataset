  test "steps after a failing leaf never have their actions invoked" do
    me = self()

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:error, :halt} end, fn _ -> :ub end)
      |> Saga.step(
        :c,
        fn _ ->
          send(me, :c_ran)
          {:ok, 3}
        end,
        fn _ -> :uc end
      )
      |> Saga.execute(%{})

    assert {:error, [:b], :halt, [a: :ua]} = result
    refute_receive :c_ran, 50
  end