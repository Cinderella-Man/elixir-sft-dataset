  test "failed applications do not consume uses" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "NOCONSUME",
        type: :fixed_amount,
        value: 500,
        max_uses: 1,
        min_order_total: 5_000
      })

    # Below minimum -> error, must NOT consume the single available use
    assert {:error, :below_min_order} = PromoCodes.apply("NOCONSUME", 1_000)

    # The one real use is still available
    assert {:ok, 500} = PromoCodes.apply("NOCONSUME", 5_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("NOCONSUME", 5_000)
  end