defmodule CartTest do
  use ExUnit.Case, async: false

  defp with_items(tax_rate) do
    cart = Cart.new(tax_rate: tax_rate)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 100.0)
    cart
  end

  test "base lifecycle still works with per-item bulk discount" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "p", 10, 10.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001

    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 0, 10.0)
    assert {:error, :not_found} = Cart.update_quantity(cart, "ghost", 3)
    {:ok, cart} = Cart.update_quantity(cart, "p", 0)
    assert Cart.calculate_totals(cart).items == []
  end

  test "percentage coupon removes a fraction of the subtotal" do
    cart = with_items(0.1)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "SAVE10", type: :percentage, value: 0.10})
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 100.0, 0.001
    assert_in_delta totals.discount, 10.0, 0.001
    assert_in_delta totals.discounted_subtotal, 90.0, 0.001
    assert_in_delta totals.tax, 9.0, 0.001
    assert_in_delta totals.grand_total, 99.0, 0.001
    assert totals.coupons == ["SAVE10"]
  end

  test "stacking applies coupons in order" do
    cart = with_items(0.0)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "PCT", type: :percentage, value: 0.10})
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "FLAT", type: :fixed, value: 20.0})
    totals = Cart.calculate_totals(cart)
    # 100 -> -10 (10%) -> 90 -> -20 (fixed) -> 70
    assert_in_delta totals.discount, 30.0, 0.001
    assert_in_delta totals.discounted_subtotal, 70.0, 0.001
    assert totals.coupons == ["PCT", "FLAT"]
  end

  test "order of coupons matters" do
    a = with_items(0.0)
    {:ok, a} = Cart.apply_coupon(a, %{code: "FLAT", type: :fixed, value: 20.0})
    {:ok, a} = Cart.apply_coupon(a, %{code: "PCT", type: :percentage, value: 0.10})
    # 100 -> -20 -> 80 -> -8 (10% of 80) -> 72
    assert_in_delta Cart.calculate_totals(a).discounted_subtotal, 72.0, 0.001

    b = with_items(0.0)
    {:ok, b} = Cart.apply_coupon(b, %{code: "PCT", type: :percentage, value: 0.10})
    {:ok, b} = Cart.apply_coupon(b, %{code: "FLAT", type: :fixed, value: 20.0})
    # 100 -> -10 -> 90 -> -20 -> 70
    assert_in_delta Cart.calculate_totals(b).discounted_subtotal, 70.0, 0.001
  end

  test "fixed coupon never pushes running amount below zero" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 50.0)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "BIG", type: :fixed, value: 80.0})
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.discount, 50.0, 0.001
    assert_in_delta totals.discounted_subtotal, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001
  end

  test "rejects duplicate coupon codes" do
    cart = with_items(0.0)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "X", type: :percentage, value: 0.10})

    assert {:error, :already_applied} =
             Cart.apply_coupon(cart, %{code: "X", type: :fixed, value: 5.0})
  end

  test "rejects coupons below the minimum subtotal" do
    cart = with_items(0.0)

    assert {:error, :below_minimum} =
             Cart.apply_coupon(cart, %{
               code: "VIP",
               type: :percentage,
               value: 0.25,
               min_subtotal: 200.0
             })
  end

  test "min_subtotal defaults to zero and always passes" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 1.0)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "ANY", type: :fixed, value: 0.5})
    assert Cart.calculate_totals(cart).coupons == ["ANY"]
  end

  test "rejects malformed coupons" do
    cart = with_items(0.0)
    assert {:error, :invalid_coupon} = Cart.apply_coupon(cart, %{type: :percentage, value: 0.1})

    assert {:error, :invalid_coupon} =
             Cart.apply_coupon(cart, %{code: "Z", type: :bogus, value: 1})

    assert {:error, :invalid_coupon} =
             Cart.apply_coupon(cart, %{code: "Z", type: :fixed, value: -1})
  end

  test "no coupons means discount is zero" do
    cart = with_items(0.1)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.discount, 0.0, 0.001
    assert_in_delta totals.discounted_subtotal, totals.subtotal, 0.001
    assert totals.coupons == []
  end

  test "min_subtotal is compared against the subtotal after per-item bulk discounts" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "bulk", 10, 10.0)
    # raw 10 x 10.0 = 100.0, but the bulk discount drops the subtotal to 90.0
    assert_in_delta Cart.calculate_totals(cart).subtotal, 90.0, 0.001

    assert {:error, :below_minimum} =
             Cart.apply_coupon(cart, %{
               code: "MIN100",
               type: :fixed,
               value: 5.0,
               min_subtotal: 100.0
             })
  end

  test "coupon whose min_subtotal exactly equals the subtotal is accepted" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 100.0)

    {:ok, cart} =
      Cart.apply_coupon(cart, %{
        code: "EXACT",
        type: :percentage,
        value: 0.10,
        min_subtotal: 100.0
      })

    totals = Cart.calculate_totals(cart)
    assert totals.coupons == ["EXACT"]
    assert_in_delta totals.discount, 10.0, 0.001
  end

  test "remove_item drops the product entirely and is a no-op for an absent product" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "a", 2, 10.0)
    {:ok, cart} = Cart.add_item(cart, "b", 3, 5.0)

    removed = Cart.remove_item(cart, "a")
    ids = Enum.map(Cart.calculate_totals(removed).items, & &1.product_id)
    assert ids == ["b"]
    assert_in_delta Cart.calculate_totals(removed).subtotal, 15.0, 0.001

    same = Cart.remove_item(removed, "ghost")
    assert Cart.calculate_totals(same) == Cart.calculate_totals(removed)
  end

  test "repeated add_item calls sum quantities and can cross the bulk threshold" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "p", 4, 10.0)
    {:ok, cart} = Cart.add_item(cart, "p", 6, 10.0)

    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 10
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001
  end

  test "add_item rejects non-integer and negative quantities" do
    cart = Cart.new(tax_rate: 0.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 1.5, 10.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", -3, 10.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", :two, 10.0)
  end

  test "update_quantity rejects a negative quantity and leaves the cart usable" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "p", 2, 10.0)
    assert {:error, :invalid_quantity} = Cart.update_quantity(cart, "p", -1)

    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 20.0, 0.001
    # :tax_rate defaults to 0.0, so no tax is added
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 20.0, 0.001
  end
end
