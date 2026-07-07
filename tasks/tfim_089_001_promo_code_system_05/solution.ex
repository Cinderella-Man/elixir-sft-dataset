  test "percentage: 50% off a $100 order returns $50" do
    {:ok, _} = PromoCodes.create(%{code: "HALF", type: :percentage, value: 50})
    assert {:ok, 5_000} = PromoCodes.apply("HALF", 10_000)
  end