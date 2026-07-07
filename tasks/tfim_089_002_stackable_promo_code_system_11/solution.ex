  test "unknown code is rejected while valid codes apply" do
    {:ok, _} = StackablePromoCodes.create(%{code: "GOOD", type: :fixed_amount, value: 250})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["GOOD", "NOPE"], 10_000)
    assert find(r.applied, "GOOD").discount == 250
    assert find(r.rejected, "NOPE").reason == :not_found
  end