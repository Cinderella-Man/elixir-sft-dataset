defmodule CartServerTest do
  use ExUnit.Case, async: false

  test "start_link defaults tax rate to zero" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 2, 10.0)
    totals = CartServer.totals(pid)
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 20.0, 0.001
  end

  test "add_item accumulates and validates quantity" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 3, 5.0)
    :ok = CartServer.add_item(pid, "a", 4, 5.0)
    [item] = CartServer.totals(pid).items
    assert item.quantity == 7
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", 0, 5.0)
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", -2, 5.0)
  end

  test "remove_item and update_quantity" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 2, 5.0)
    :ok = CartServer.update_quantity(pid, "a", 8)
    [item] = CartServer.totals(pid).items
    assert item.quantity == 8

    assert {:error, :not_found} = CartServer.update_quantity(pid, "ghost", 3)
    assert {:error, :invalid_quantity} = CartServer.update_quantity(pid, "a", -1)

    :ok = CartServer.update_quantity(pid, "a", 0)
    assert CartServer.totals(pid).items == []

    :ok = CartServer.add_item(pid, "b", 1, 1.0)
    :ok = CartServer.remove_item(pid, "b")
    assert CartServer.totals(pid).items == []
    assert CartServer.remove_item(pid, "missing") == :ok
  end

  test "per-item discount at threshold and tax on discounted subtotal" do
    {:ok, pid} = CartServer.start_link(tax_rate: 0.1)
    :ok = CartServer.add_item(pid, "a", 9, 10.0)
    [nine] = CartServer.totals(pid).items
    assert nine.discount_rate == 0.0
    assert_in_delta nine.line_total, 90.0, 0.001

    :ok = CartServer.update_quantity(pid, "a", 10)
    totals = CartServer.totals(pid)
    [ten] = totals.items
    assert ten.discount_rate == 0.1
    assert_in_delta ten.line_total, 90.0, 0.001
    assert_in_delta totals.subtotal, 90.0, 0.001
    assert_in_delta totals.tax, 9.0, 0.001
    assert_in_delta totals.grand_total, 99.0, 0.001
  end

  test "concurrent adds to the same product accumulate with no lost updates" do
    {:ok, pid} = CartServer.start_link()

    1..100
    |> Enum.map(fn _ -> Task.async(fn -> CartServer.add_item(pid, "p", 1, 2.0) end) end)
    |> Task.await_many(5000)

    [item] = CartServer.totals(pid).items
    assert item.quantity == 100
    # quantity 100 >= 10 triggers the 10% bulk discount: 2.0 * 0.9 * 100 = 180.0
    assert_in_delta CartServer.totals(pid).subtotal, 180.0, 0.001
  end

  test "concurrent adds across distinct products all land" do
    {:ok, pid} = CartServer.start_link()

    1..50
    |> Enum.map(fn i -> Task.async(fn -> CartServer.add_item(pid, "p#{i}", 1, 1.0) end) end)
    |> Task.await_many(5000)

    assert length(CartServer.totals(pid).items) == 50
  end

  test "each cart process holds independent state" do
    {:ok, a} = CartServer.start_link()
    {:ok, b} = CartServer.start_link()
    :ok = CartServer.add_item(a, "x", 5, 10.0)
    assert length(CartServer.totals(a).items) == 1
    assert CartServer.totals(b).items == []
  end

  test "every item map exposes all five documented keys" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 3, 4.0)

    [item] = CartServer.totals(pid).items

    for key <- [:product_id, :quantity, :unit_price, :discount_rate, :line_total] do
      assert Map.has_key?(item, key), "item map is missing #{inspect(key)}"
    end
  end

  test "product_id and unit_price identify each line among several items" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "widget", 2, 5.0)
    :ok = CartServer.add_item(pid, "gadget", 3, 7.0)

    by_id =
      CartServer.totals(pid).items
      |> Map.new(fn item -> {item.product_id, item} end)

    assert Map.keys(by_id) |> Enum.sort() == ["gadget", "widget"]

    widget = by_id["widget"]
    assert widget.quantity == 2
    assert_in_delta widget.unit_price, 5.0, 0.001
    assert widget.discount_rate == 0.0
    assert_in_delta widget.line_total, 10.0, 0.001

    gadget = by_id["gadget"]
    assert gadget.quantity == 3
    assert_in_delta gadget.unit_price, 7.0, 0.001
    assert gadget.discount_rate == 0.0
    assert_in_delta gadget.line_total, 21.0, 0.001
  end

  test "accumulated item keeps the product_id and unit_price it was added with" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, :sku_42, 2, 3.0)
    :ok = CartServer.add_item(pid, :sku_42, 5, 3.0)

    [item] = CartServer.totals(pid).items
    assert item.product_id == :sku_42
    assert item.quantity == 7
    assert_in_delta item.unit_price, 3.0, 0.001
    assert item.discount_rate == 0.0
    assert_in_delta item.line_total, 21.0, 0.001
  end

  test "add_item rejects non-integer quantities and leaves the cart untouched" do
    {:ok, pid} = CartServer.start_link()

    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", 2.0, 5.0)
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", 1.5, 5.0)
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", "3", 5.0)
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", :two, 5.0)

    assert CartServer.totals(pid).items == []
  end

  test "subtotal sums discounted and undiscounted lines together with tax on top" do
    {:ok, pid} = CartServer.start_link(tax_rate: 0.05)
    :ok = CartServer.add_item(pid, "bulk", 10, 10.0)
    :ok = CartServer.add_item(pid, "single", 2, 5.0)

    totals = CartServer.totals(pid)
    by_id = Map.new(totals.items, fn item -> {item.product_id, item} end)

    assert by_id["bulk"].discount_rate == 0.1
    assert_in_delta by_id["bulk"].line_total, 90.0, 0.001
    assert by_id["single"].discount_rate == 0.0
    assert_in_delta by_id["single"].line_total, 10.0, 0.001

    assert_in_delta totals.subtotal, 100.0, 0.001
    assert_in_delta totals.tax, 5.0, 0.001
    assert_in_delta totals.grand_total, 105.0, 0.001
  end

  test "accumulated adds crossing the bulk threshold earn the discount" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 6, 10.0)

    [before] = CartServer.totals(pid).items
    assert before.discount_rate == 0.0
    assert_in_delta before.line_total, 60.0, 0.001

    :ok = CartServer.add_item(pid, "a", 4, 10.0)

    [after_bulk] = CartServer.totals(pid).items
    assert after_bulk.quantity == 10
    assert after_bulk.discount_rate == 0.1
    assert_in_delta after_bulk.line_total, 90.0, 0.001
  end

  test "empty cart reports zero subtotal, tax and grand total" do
    {:ok, pid} = CartServer.start_link(tax_rate: 0.2)

    totals = CartServer.totals(pid)
    assert totals.items == []
    assert_in_delta totals.subtotal, 0.0, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001

    :ok = CartServer.add_item(pid, "a", 1, 10.0)
    :ok = CartServer.remove_item(pid, "a")

    emptied = CartServer.totals(pid)
    assert emptied.items == []
    assert_in_delta emptied.subtotal, 0.0, 0.001
    assert_in_delta emptied.tax, 0.0, 0.001
    assert_in_delta emptied.grand_total, 0.0, 0.001
  end
end
