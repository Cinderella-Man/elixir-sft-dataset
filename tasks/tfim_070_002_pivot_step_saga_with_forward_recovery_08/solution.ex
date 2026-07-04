  test "retriable action sees context enriched by prior steps" do
    Saga.new()
    |> Saga.step(:seed, fn _ -> {:ok, 41} end, fn _ -> nil end)
    |> Saga.retriable(
      :p,
      fn ctx ->
        track(:seen, ctx.seed)
        {:ok, ctx.seed + 1}
      end,
      2
    )
    |> Saga.execute(%{})

    assert tracked(:seen) == [41]
  end