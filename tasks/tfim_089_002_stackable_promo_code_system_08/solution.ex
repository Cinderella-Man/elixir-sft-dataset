  test "free shipping stacks with a percentage" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P10", type: :percentage, value: 10})
    {:ok, _} = StackablePromoCodes.create(%{code: "SHIP", type: :free_shipping, value: 999})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["P10", "SHIP"], 10_000)
    assert find(r.applied, "P10").discount == 1_000
    assert find(r.applied, "SHIP").discount == 999
    assert r.total_discount == 1_999
    assert r.final_total == 8_001
  end