  test "free_shipping still respects the minimum order total" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "FREESHIPMIN",
        type: :free_shipping,
        value: 999,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("FREESHIPMIN", 3_000)
    assert {:ok, 999} = PromoCodes.apply("FREESHIPMIN", 5_000)
  end