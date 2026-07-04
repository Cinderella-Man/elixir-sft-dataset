  test "compensation results are included in the error tuple, in reverse order" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, :a_ok} end, fn _ctx -> :a_compensated end)
      |> Saga.step(:b, fn _ctx -> {:ok, :b_ok} end, fn _ctx -> :b_compensated end)
      |> Saga.step(:c, fn _ctx -> {:error, :c_failed} end, fn _ctx -> :c_compensated end)
      |> Saga.execute(%{})

    assert {:error, :c, :c_failed, comp} = result
    assert comp == [b: :b_compensated, a: :a_compensated]
  end