  test "percentage discount rounds a fractional result to the nearest cent" do
    {:ok, _} = PromoCodes.create(%{code: "R33", type: :percentage, value: 33})

    # 999 * 33 / 100 == 329.67 -> rounds up to 330 (truncation would give 329)
    assert {:ok, 330} = PromoCodes.apply("R33", 999)

    # 1001 * 33 / 100 == 330.33 -> rounds down to 330 (ceiling would give 331)
    assert {:ok, 330} = PromoCodes.apply("R33", 1_001)
  end