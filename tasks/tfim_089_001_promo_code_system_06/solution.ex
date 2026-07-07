  test "percentage: 20% off a $100 order returns $20" do
    {:ok, _} = PromoCodes.create(%{code: "TWENTY", type: :percentage, value: 20})
    assert {:ok, 2_000} = PromoCodes.apply("TWENTY", 10_000)
  end