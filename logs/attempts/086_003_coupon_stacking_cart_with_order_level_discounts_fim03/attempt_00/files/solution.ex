def apply_coupon(%Cart{} = cart, coupon) do
  with :ok <- validate_coupon(coupon),
       :ok <- ensure_not_applied(cart, coupon),
       :ok <- ensure_minimum(cart, coupon) do
    {:ok, %Cart{cart | coupons: cart.coupons ++ [normalize(coupon)]}}
  end
end