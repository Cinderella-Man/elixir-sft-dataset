  test "applying an unknown code returns :not_found" do
    assert {:error, :not_found} = PromoCodes.apply("NOPE", 10_000)
  end