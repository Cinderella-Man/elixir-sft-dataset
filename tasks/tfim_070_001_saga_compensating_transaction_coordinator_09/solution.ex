  test "all compensations run even if one raises an exception" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, :ok} end, fn _ctx ->
        track(:ran, :a)
        raise "oops from compensation A"
      end)
      |> Saga.step(:b, fn _ctx -> {:ok, :ok} end, fn _ctx ->
        track(:ran, :b)
      end)
      |> Saga.step(:c, fn _ctx -> {:error, :fail} end, fn _ctx ->
        track(:ran, :c)
      end)
      |> Saga.execute(%{})

    # Both a and b should have been compensated despite a raising
    assert :b in tracked(:ran)
    assert :a in tracked(:ran)
    # The overall result is still an error tuple
    assert {:error, :c, :fail, _} = result
  end