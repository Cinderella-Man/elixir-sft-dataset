  test "compensations run in reverse order when step 2 of 3 fails" do
    Saga.new()
    |> Saga.step(
      :reserve,
      fn _ctx -> {:ok, :reserved} end,
      fn _ctx -> track(:comp_order, :reserve) end
    )
    |> Saga.step(
      :charge,
      fn _ctx -> {:error, :card_declined} end,
      fn _ctx -> track(:comp_order, :charge) end
    )
    |> Saga.step(
      :notify,
      fn _ctx -> {:ok, :notified} end,
      fn _ctx -> track(:comp_order, :notify) end
    )
    |> Saga.execute(%{})

    # :charge never succeeded, so only :reserve should be compensated
    # :notify never ran, so it should not be compensated
    assert tracked(:comp_order) == [:reserve]
  end