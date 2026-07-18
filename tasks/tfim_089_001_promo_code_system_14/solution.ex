  test "expired code returns :expired" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "OLD",
        type: :percentage,
        value: 10,
        valid_until: @past
      })

    assert {:error, :expired} = PromoCodes.apply("OLD", 10_000)
  end