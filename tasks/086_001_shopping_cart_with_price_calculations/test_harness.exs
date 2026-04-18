defmodule CartTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Cart creation
  # -------------------------------------------------------

  test "new/0 creates an empty cart with default tax rate" do
    cart = Cart.new()
    assert cart.tax_rate == 0.0
    assert cart.items == %{}
  end

  test "new/1 accepts a custom tax rate" do
    cart = Cart.new(tax_rate: 0.1)
    assert cart.tax_rate == 0.1
  end

  # -------------------------------------------------------
  # add_item
  # -------------------------------------------------------

  test "add_item adds a new product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    totals = Cart.calculate_totals(cart)
    assert length(totals.items) == 1
    [item] = totals.items
    assert item.product_id == "prod:1"
    assert item.quantity == 2
    assert item.unit_price == 5.0
  end

  test "add_item accumulates quantity for existing product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 3, 5.0)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 4, 5.0)
    totals = Cart.calculate_totals(cart)
    [item] = totals.items
    assert item.quantity == 7
  end

  test "add_item rejects zero quantity" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", 0, 5.0)
  end

  test "add_item rejects negative quantity" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", -1, 5.0)
  end

  # -------------------------------------------------------
  # remove_item
  # -------------------------------------------------------

  test "remove_item removes an existing product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    cart = Cart.remove_item(cart, "prod:1")
    totals = Cart.calculate_totals(cart)
    assert totals.items == []
  end

  test "remove_item is a no-op for unknown product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    cart2 = Cart.remove_item(cart, "prod:999")
    assert Cart.calculate_totals(cart2).items == Cart.calculate_totals(cart).items
  end

  # -------------------------------------------------------
  # update_quantity
  # -------------------------------------------------------

  test "update_quantity changes the quantity of an item" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    {:ok, cart} = Cart.update_quantity(cart, "prod:1", 8)
    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 8
  end

  test "update_quantity to 0 removes the item" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    {:ok, cart} = Cart.update_quantity(cart, "prod:1", 0)
    assert Cart.calculate_totals(cart).items == []
  end

  test "update_quantity returns error for unknown product" do
    cart = Cart.new()
    assert {:error, :not_found} = Cart.update_quantity(cart, "prod:999", 5)
  end

  test "update_quantity rejects negative quantity" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    assert {:error, :invalid_quantity} = Cart.update_quantity(cart, "prod:1", -3)
  end

  # -------------------------------------------------------
  # Discount threshold
  # -------------------------------------------------------

  test "9 items: no discount applied" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 9, 10.0)
    totals = Cart.calculate_totals(cart)
    [item] = totals.items
    assert item.discount_rate == 0.0
    assert_in_delta item.line_total, 90.0, 0.001
    assert_in_delta totals.subtotal, 90.0, 0.001
  end

  test "10 items: 10% discount applied" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    totals = Cart.calculate_totals(cart)
    [item] = totals.items
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001
    assert_in_delta totals.subtotal, 90.0, 0.001
  end

  test "discount threshold is per line item, not per cart" do
    cart = Cart.new()
    # discounted
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    # not discounted
    {:ok, cart} = Cart.add_item(cart, "prod:2", 3, 20.0)
    totals = Cart.calculate_totals(cart)

    discounted = Enum.find(totals.items, &(&1.product_id == "prod:1"))
    full_price = Enum.find(totals.items, &(&1.product_id == "prod:2"))

    assert discounted.discount_rate == 0.1
    assert full_price.discount_rate == 0.0
    assert_in_delta discounted.line_total, 90.0, 0.001
    assert_in_delta full_price.line_total, 60.0, 0.001
  end

  # -------------------------------------------------------
  # Tax calculation
  # -------------------------------------------------------

  test "tax is applied on top of the discounted subtotal" do
    cart = Cart.new(tax_rate: 0.1)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    # line_total = 90.0, tax = 9.0, grand_total = 99.0
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 90.0, 0.001
    assert_in_delta totals.tax, 9.0, 0.001
    assert_in_delta totals.grand_total, 99.0, 0.001
  end

  test "zero tax rate produces no tax" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 50.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, totals.subtotal, 0.001
  end

  # -------------------------------------------------------
  # Empty cart
  # -------------------------------------------------------

  test "calculate_totals on empty cart returns all zeros" do
    cart = Cart.new(tax_rate: 0.08)
    totals = Cart.calculate_totals(cart)
    assert totals.items == []
    assert_in_delta totals.subtotal, 0.0, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001
  end

  # -------------------------------------------------------
  # Multi-step scenario
  # -------------------------------------------------------

  test "full lifecycle: add, update, remove, recalculate" do
    cart = Cart.new(tax_rate: 0.05)

    # 100.0, no discount
    {:ok, cart} = Cart.add_item(cart, "a", 5, 20.0)
    # 72.0 after 10% discount
    {:ok, cart} = Cart.add_item(cart, "b", 10, 8.0)
    # 50.0, no discount
    {:ok, cart} = Cart.add_item(cart, "c", 1, 50.0)

    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 222.0, 0.001

    # Bump "a" over the discount threshold
    # now 180.0 after discount
    {:ok, cart} = Cart.update_quantity(cart, "a", 10)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 302.0, 0.001

    # Remove "c"
    cart = Cart.remove_item(cart, "c")
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 252.0, 0.001
    assert_in_delta totals.tax, 252.0 * 0.05, 0.001
    assert_in_delta totals.grand_total, 252.0 * 1.05, 0.001
  end
end
