  test "only one free shipping code applies" do
    {:ok, _} = StackablePromoCodes.create(%{code: "S1", type: :free_shipping, value: 500})
    {:ok, _} = StackablePromoCodes.create(%{code: "S2", type: :free_shipping, value: 700})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["S1", "S2"], 10_000)
    assert find(r.applied, "S1").discount == 500
    assert find(r.rejected, "S2").reason == :free_shipping_already_applied
  end