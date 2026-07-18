  test "every retry of a retriable action receives the identical context map" do
    result =
      Saga.new()
      |> Saga.step(:seed, fn _ -> {:ok, :s} end, fn _ -> nil end)
      |> Saga.retriable(
        :commit,
        fn ctx ->
          track(:ctxs, ctx)
          if length(tracked(:ctxs)) < 3, do: {:error, :flaky}, else: {:ok, :done}
        end,
        4
      )
      |> Saga.execute(%{base: 7})

    assert {:ok, _} = result
    seen = tracked(:ctxs)
    assert length(seen) == 3
    assert Enum.uniq(seen) == [%{base: 7, seed: :s}]
  end