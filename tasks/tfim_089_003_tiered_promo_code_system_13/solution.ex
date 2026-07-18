  test "unknown code returns :not_found" do
    assert {:error, :not_found} = TieredPromoCodes.apply_code("NOPE", 10_000)
  end