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
    assert_in_delta CartServer.totals(pid).subtotal, 200.0, 0.001
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
end