  test "fixed_amount: $15 off returns 1500" do
    {:ok, _} = PromoCodes.create(%{code: "FIX15", type: :fixed_amount, value: 1_500})
    assert {:ok, 1_500} = PromoCodes.apply("FIX15", 10_000)
  end