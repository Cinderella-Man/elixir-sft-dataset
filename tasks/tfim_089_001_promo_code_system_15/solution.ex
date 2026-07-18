  test "code inside its validity window applies successfully" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "NOW",
        type: :percentage,
        value: 10,
        valid_from: @past,
        valid_until: @future
      })

    assert {:ok, 1_000} = PromoCodes.apply("NOW", 10_000)
  end