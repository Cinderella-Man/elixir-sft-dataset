  test "exception raised inside a compensation is recorded in the compensation results" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, :a_ok} end, fn _ctx -> raise "boom from a" end)
      |> Saga.step(:b, fn _ctx -> {:ok, :b_ok} end, fn _ctx -> :b_done end)
      |> Saga.step(:c, fn _ctx -> {:error, :fail} end, fn _ctx -> :c_done end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, comp} = result
    # every completed step has an entry, in reverse execution order
    assert Keyword.keys(comp) == [:b, :a]
    assert comp[:b] == :b_done
    # the caught exception itself must be recorded as :a's result
    assert comp[:a] != nil
    assert comp[:a] != :a_ok
  end