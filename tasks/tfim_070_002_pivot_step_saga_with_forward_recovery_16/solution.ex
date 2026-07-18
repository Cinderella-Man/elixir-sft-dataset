  test "compensating functions receive the context accumulated up to the failure" do
    result =
      Saga.new()
      |> Saga.step(:a, fn ctx -> {:ok, ctx.init} end, fn ctx ->
        track(:comp_ctx, ctx)
        :ca
      end)
      |> Saga.step(:b, fn _ -> {:ok, :bee} end, fn ctx ->
        track(:comp_ctx, ctx)
        :cb
      end)
      |> Saga.step(:c, fn _ -> {:error, :boom} end, fn _ -> :cc end)
      |> Saga.execute(%{init: :z})

    assert {:error, :c, :boom, [b: :cb, a: :ca]} = result
    assert tracked(:comp_ctx) == [%{init: :z, a: :z, b: :bee}, %{init: :z, a: :z, b: :bee}]
  end