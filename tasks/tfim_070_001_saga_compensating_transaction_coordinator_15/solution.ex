  test "three completed steps are compensated in reverse invocation order" do
    Saga.new()
    |> Saga.step(:one, fn _ctx -> {:ok, 1} end, fn _ctx -> track(:calls, :one) end)
    |> Saga.step(:two, fn _ctx -> {:ok, 2} end, fn _ctx -> track(:calls, :two) end)
    |> Saga.step(:three, fn _ctx -> {:ok, 3} end, fn _ctx -> track(:calls, :three) end)
    |> Saga.step(:four, fn _ctx -> {:error, :nope} end, fn _ctx -> track(:calls, :four) end)
    |> Saga.execute(%{})

    assert tracked(:calls) == [:three, :two, :one]
  end