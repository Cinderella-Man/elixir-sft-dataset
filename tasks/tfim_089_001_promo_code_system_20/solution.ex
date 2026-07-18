  test "percentage discount combined with a minimum order total" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "COMBO",
        type: :percentage,
        value: 50,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("COMBO", 3_000)
    assert {:ok, 5_000} = PromoCodes.apply("COMBO", 10_000)
    assert {:ok, 2_500} = PromoCodes.apply("COMBO", 5_000)
  end