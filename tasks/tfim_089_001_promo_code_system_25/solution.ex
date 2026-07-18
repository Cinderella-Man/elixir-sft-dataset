  test "different codes are tracked independently" do
    {:ok, _} = PromoCodes.create(%{code: "A", type: :percentage, value: 10, max_uses: 1})
    {:ok, _} = PromoCodes.create(%{code: "B", type: :fixed_amount, value: 250})

    assert {:ok, 1_000} = PromoCodes.apply("A", 10_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("A", 10_000)

    # B is completely unaffected by A being exhausted
    assert {:ok, 250} = PromoCodes.apply("B", 10_000)
    assert {:ok, 250} = PromoCodes.apply("B", 10_000)
  end