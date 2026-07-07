  test "from_major/2 rounds halves away from zero" do
    # 0.005 USD -> 0.5 cents -> 1
    assert Money.from_major(0.005, :USD).amount == 1
  end