  test "validity boundaries are inclusive" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    # now == valid_from == valid_until
    assert {:ok, 1_000} = PromoCodes.apply("EDGE", 10_000)
  end