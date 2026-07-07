  test "fixed_amount never exceeds the order total" do
    {:ok, _} = PromoCodes.create(%{code: "BIG", type: :fixed_amount, value: 5_000})
    assert {:ok, 3_000} = PromoCodes.apply("BIG", 3_000)
  end