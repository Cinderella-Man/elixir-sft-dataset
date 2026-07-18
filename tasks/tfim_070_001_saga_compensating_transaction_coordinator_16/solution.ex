  test "compensation returning an error tuple is recorded and does not abort the chain" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, :a_ok} end, fn _ctx ->
        track(:ran_comp, :a)
        :a_undone
      end)
      |> Saga.step(:b, fn _ctx -> {:ok, :b_ok} end, fn _ctx ->
        track(:ran_comp, :b)
        {:error, :compensation_broke}
      end)
      |> Saga.step(:c, fn _ctx -> {:error, :fail} end, fn _ctx -> nil end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, comp} = result
    assert tracked(:ran_comp) == [:b, :a]
    assert comp == [b: {:error, :compensation_broke}, a: :a_undone]
  end