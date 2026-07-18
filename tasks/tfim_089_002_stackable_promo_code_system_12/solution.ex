  test "duplicate code in the same order is rejected once" do
    {:ok, _} = StackablePromoCodes.create(%{code: "F5", type: :fixed_amount, value: 500})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["F5", "F5"], 10_000)
    assert length(Enum.filter(r.applied, &(&1.code == "F5"))) == 1
    assert find(r.rejected, "F5").reason == :duplicate_in_order
  end