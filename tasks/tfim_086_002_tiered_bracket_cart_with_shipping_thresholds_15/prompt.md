# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule Cart do
  @moduledoc """
  An in-memory shopping cart with tiered bulk-discount brackets and
  shipping-threshold logic.

  Each line item receives the highest applicable quantity-bracket discount.
  Shipping is a flat cost that may be waived once the discounted subtotal
  reaches a configured threshold.  Tax is charged on the discounted subtotal
  only — never on shipping.
  """

  @default_tiers [{10, 0.05}, {25, 0.10}, {50, 0.15}]

  defmodule Item do
    @moduledoc "A single line item inside a `Cart`."
    @enforce_keys [:product_id, :quantity, :unit_price]
    defstruct [:product_id, :quantity, :unit_price]
  end

  @enforce_keys [:tax_rate, :items, :discount_tiers, :shipping_flat, :free_shipping_threshold]
  defstruct tax_rate: 0.0,
            items: %{},
            discount_tiers: @default_tiers,
            shipping_flat: 0.0,
            free_shipping_threshold: nil

  @doc "Creates a new, empty cart. See the module doc for supported options."
  @spec new(keyword()) :: %Cart{}
  def new(opts \\ []) do
    %Cart{
      tax_rate: Keyword.get(opts, :tax_rate, 0.0),
      items: %{},
      discount_tiers: Keyword.get(opts, :discount_tiers, @default_tiers),
      shipping_flat: Keyword.get(opts, :shipping_flat, 0.0),
      free_shipping_threshold: Keyword.get(opts, :free_shipping_threshold, nil)
    }
  end

  @doc "Adds `quantity` of `product_id` at `unit_price`, summing existing quantities."
  @spec add_item(%Cart{}, term(), pos_integer(), float()) ::
          {:ok, %Cart{}} | {:error, :invalid_quantity}
  def add_item(%Cart{} = cart, product_id, quantity, unit_price)
      when is_integer(quantity) and quantity > 0 do
    updated =
      Map.update(
        cart.items,
        product_id,
        %Item{product_id: product_id, quantity: quantity, unit_price: unit_price},
        fn %Item{} = existing -> %Item{existing | quantity: existing.quantity + quantity} end
      )

    {:ok, %Cart{cart | items: updated}}
  end

  def add_item(%Cart{}, _product_id, _quantity, _unit_price),
    do: {:error, :invalid_quantity}

  @doc "Removes `product_id` entirely; a no-op when absent."
  @spec remove_item(%Cart{}, term()) :: %Cart{}
  def remove_item(%Cart{} = cart, product_id),
    do: %Cart{cart | items: Map.delete(cart.items, product_id)}

  @doc "Sets an existing item's quantity; 0 removes it."
  @spec update_quantity(%Cart{}, term(), non_neg_integer()) ::
          {:ok, %Cart{}} | {:error, :not_found | :invalid_quantity}
  def update_quantity(%Cart{} = cart, product_id, quantity)
      when is_integer(quantity) and quantity >= 0 do
    case Map.fetch(cart.items, product_id) do
      :error ->
        {:error, :not_found}

      {:ok, _item} when quantity == 0 ->
        {:ok, remove_item(cart, product_id)}

      {:ok, %Item{} = item} ->
        updated = Map.put(cart.items, product_id, %Item{item | quantity: quantity})
        {:ok, %Cart{cart | items: updated}}
    end
  end

  def update_quantity(%Cart{}, _product_id, _quantity),
    do: {:error, :invalid_quantity}

  @doc "Computes the totals map for the cart's current state."
  @spec calculate_totals(%Cart{}) :: %{
          subtotal: float(),
          tax: float(),
          shipping: float(),
          grand_total: float(),
          items: [map()]
        }
  def calculate_totals(%Cart{} = cart) do
    items =
      cart.items
      |> Map.values()
      |> Enum.map(&build_summary(&1, cart.discount_tiers))

    subtotal = Enum.reduce(items, 0.0, fn i, acc -> acc + i.line_total end)
    tax = subtotal * cart.tax_rate
    shipping = shipping_cost(items, subtotal, cart)

    %{
      items: items,
      subtotal: subtotal,
      tax: tax,
      shipping: shipping,
      grand_total: subtotal + tax + shipping
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_summary(%Item{} = item, tiers) do
    rate = discount_for(item.quantity, tiers)

    %{
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      discount_rate: rate,
      line_total: item.unit_price * (1.0 - rate) * item.quantity
    }
  end

  defp discount_for(quantity, tiers) do
    tiers
    |> Enum.filter(fn {min, _rate} -> quantity >= min end)
    |> case do
      [] -> 0.0
      applicable -> applicable |> Enum.max_by(fn {min, _rate} -> min end) |> elem(1)
    end
  end

  defp shipping_cost([], _subtotal, _cart), do: 0.0

  defp shipping_cost(_items, subtotal, %Cart{
         free_shipping_threshold: threshold,
         shipping_flat: flat
       }) do
    if is_number(threshold) and subtotal >= threshold, do: 0.0, else: flat
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule CartTest do
  use ExUnit.Case, async: false

  test "new/0 uses defaults" do
    cart = Cart.new()
    assert cart.tax_rate == 0.0
    assert cart.shipping_flat == 0.0
    assert cart.free_shipping_threshold == nil
    assert cart.discount_tiers == [{10, 0.05}, {25, 0.10}, {50, 0.15}]
    assert cart.items == %{}
  end

  test "add_item accumulates and rejects bad quantities" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "p", 2, 5.0)
    {:ok, cart} = Cart.add_item(cart, "p", 3, 5.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 5
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 0, 5.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", -1, 5.0)
  end

  test "remove_item and update_quantity" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "p", 4, 5.0)
    {:ok, cart} = Cart.update_quantity(cart, "p", 7)
    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 7
    {:ok, cart} = Cart.update_quantity(cart, "p", 0)
    assert Cart.calculate_totals(cart).items == []
    assert {:error, :not_found} = Cart.update_quantity(cart, "nope", 3)

    {:ok, cart} = Cart.add_item(cart, "p", 1, 1.0)
    assert {:error, :invalid_quantity} = Cart.update_quantity(cart, "p", -2)
    cart = Cart.remove_item(cart, "p")
    assert Cart.calculate_totals(cart).items == []
    assert Cart.remove_item(cart, "ghost") == cart
  end

  test "bracket tiers pick the highest applicable rate" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "a", 9, 10.0)
    {:ok, cart} = Cart.add_item(cart, "b", 10, 10.0)
    {:ok, cart} = Cart.add_item(cart, "c", 25, 10.0)
    {:ok, cart} = Cart.add_item(cart, "d", 50, 10.0)
    items = Cart.calculate_totals(cart).items

    a = Enum.find(items, &(&1.product_id == "a"))
    b = Enum.find(items, &(&1.product_id == "b"))
    c = Enum.find(items, &(&1.product_id == "c"))
    d = Enum.find(items, &(&1.product_id == "d"))

    assert a.discount_rate == 0.0
    assert b.discount_rate == 0.05
    assert c.discount_rate == 0.10
    assert d.discount_rate == 0.15

    assert_in_delta a.line_total, 90.0, 0.001
    assert_in_delta b.line_total, 95.0, 0.001
    assert_in_delta c.line_total, 225.0, 0.001
    assert_in_delta d.line_total, 425.0, 0.001
  end

  test "custom discount tiers override defaults" do
    cart = Cart.new(discount_tiers: [{5, 0.20}])
    {:ok, cart} = Cart.add_item(cart, "a", 5, 10.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.discount_rate == 0.20
    assert_in_delta item.line_total, 40.0, 0.001
  end

  test "tax is charged on the discounted subtotal, not on shipping" do
    cart = Cart.new(tax_rate: 0.1, shipping_flat: 5.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 100.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 100.0, 0.001
    assert_in_delta totals.tax, 10.0, 0.001
    assert_in_delta totals.shipping, 5.0, 0.001
    assert_in_delta totals.grand_total, 115.0, 0.001
  end

  test "shipping is waived at or above the free-shipping threshold" do
    cart = Cart.new(shipping_flat: 5.0, free_shipping_threshold: 100.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 50.0)
    assert_in_delta Cart.calculate_totals(cart).shipping, 5.0, 0.001

    {:ok, cart} = Cart.update_quantity(cart, "a", 3)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 150.0, 0.001
    assert_in_delta totals.shipping, 0.0, 0.001
  end

  test "empty cart charges no shipping and zero totals" do
    cart = Cart.new(tax_rate: 0.08, shipping_flat: 9.99, free_shipping_threshold: 100.0)
    totals = Cart.calculate_totals(cart)
    assert totals.items == []
    assert_in_delta totals.subtotal, 0.0, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.shipping, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001
  end

  test "shipping is waived when the discounted subtotal exactly equals the threshold" do
    cart = Cart.new(shipping_flat: 6.5, free_shipping_threshold: 100.0)
    {:ok, cart} = Cart.add_item(cart, "a", 4, 25.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 100.0, 0.001
    assert_in_delta totals.shipping, 0.0, 0.001
    assert_in_delta totals.grand_total, 100.0, 0.001
  end

  test "threshold compares against the discounted subtotal, not the undiscounted one" do
    cart = Cart.new(shipping_flat: 4.0, free_shipping_threshold: 100.0)
    {:ok, cart} = Cart.add_item(cart, "a", 10, 10.5)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 99.75, 0.001
    assert_in_delta totals.shipping, 4.0, 0.001
  end

  test "add_item rejects non-integer quantities" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 2.5, 5.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 1.0, 5.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", "3", 5.0)
    assert Cart.calculate_totals(cart).items == []
  end

  test "each totals item map carries the unit_price and every documented key" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "a", 3, 12.5)
    {:ok, cart} = Cart.add_item(cart, "a", 7, 12.5)
    [item] = Cart.calculate_totals(cart).items
    assert item.product_id == "a"
    assert item.quantity == 10
    assert item.unit_price == 12.5
    assert item.discount_rate == 0.05
    assert_in_delta item.line_total, 118.75, 0.001

    assert Map.keys(item) |> Enum.sort() ==
             [:discount_rate, :line_total, :product_id, :quantity, :unit_price]
  end

  test "a nil threshold never waives shipping no matter how large the subtotal" do
    cart = Cart.new(shipping_flat: 7.5)
    {:ok, cart} = Cart.add_item(cart, "a", 100, 500.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 42_500.0, 0.001
    assert_in_delta totals.shipping, 7.5, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 42_507.5, 0.001
  end

  test "highest applicable tier wins regardless of tier list order" do
    # TODO
  end
end
```
