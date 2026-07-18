  test "expiry is reported before the minimum order total check" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "PRECEXP",
        type: :percentage,
        value: 10,
        min_order_total: 5_000,
        valid_until: @past
      })

    # Order is also below the minimum, but expiry is evaluated first.
    assert {:error, :expired} = PromoCodes.apply("PRECEXP", 1_000)
  end