  test "not-yet-valid code returns :not_yet_valid" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "SOON",
        type: :percentage,
        value: 10,
        valid_from: @future
      })

    assert {:error, :not_yet_valid} = PromoCodes.apply("SOON", 10_000)
  end