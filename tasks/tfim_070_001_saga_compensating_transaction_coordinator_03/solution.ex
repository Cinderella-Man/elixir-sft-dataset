  test "happy path calls no compensations" do
    Saga.new()
    |> Saga.step(
      :a,
      fn _ctx -> {:ok, :done} end,
      fn _ctx -> track(:compensated, :a) end
    )
    |> Saga.execute(%{})

    assert tracked(:compensated) == []
  end