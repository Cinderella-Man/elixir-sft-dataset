  test "min_order_total defaults to zero so any order total passes the check" do
    {:ok, _} = PromoCodes.create(%{code: "NOMIN", type: :percentage, value: 10})

    assert {:ok, 0} = PromoCodes.apply("NOMIN", 0)
    assert {:ok, 1} = PromoCodes.apply("NOMIN", 5)
    assert {:ok, 1_000} = PromoCodes.apply("NOMIN", 10_000)
  end