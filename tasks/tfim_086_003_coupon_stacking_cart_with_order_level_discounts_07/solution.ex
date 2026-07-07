  test "rejects duplicate coupon codes" do
    cart = with_items(0.0)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "X", type: :percentage, value: 0.10})
    assert {:error, :already_applied} =
             Cart.apply_coupon(cart, %{code: "X", type: :fixed, value: 5.0})
  end