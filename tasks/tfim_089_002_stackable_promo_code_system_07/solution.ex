  test "only the highest percentage code applies; others rejected" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P20", type: :percentage, value: 20})
    {:ok, _} = StackablePromoCodes.create(%{code: "P50", type: :percentage, value: 50})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["P20", "P50"], 10_000)
    assert find(r.applied, "P50").discount == 5_000
    assert find(r.applied, "P20") == nil
    assert find(r.rejected, "P20").reason == :percentage_already_applied
    assert r.total_discount == 5_000
  end