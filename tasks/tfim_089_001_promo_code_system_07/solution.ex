  test "percentage discount is an integer (rounded)" do
    {:ok, _} = PromoCodes.create(%{code: "THIRD", type: :percentage, value: 33})
    assert {:ok, discount} = PromoCodes.apply("THIRD", 10_000)
    assert discount == 3_300
    assert is_integer(discount)
  end