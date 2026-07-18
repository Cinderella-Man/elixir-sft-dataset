  test "order below minimum returns :below_min_order" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "MIN50",
        type: :percentage,
        value: 10,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("MIN50", 3_000)
  end