  test "order exactly at the minimum passes" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "MIN50EQ",
        type: :percentage,
        value: 10,
        min_order_total: 5_000
      })

    assert {:ok, 500} = PromoCodes.apply("MIN50EQ", 5_000)
  end