  test "later steps see the results of earlier steps in the context" do
    saga =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, 10} end, comp(:a))
      |> Saga.step(:b, fn ctx -> {:ok, ctx.a + 5} end, comp(:b))

    assert {:ok, %{a: 10, b: 15}} = Saga.execute(saga, %{})
  end