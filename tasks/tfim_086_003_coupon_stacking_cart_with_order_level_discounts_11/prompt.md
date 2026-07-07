# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Cart do
  @moduledoc """
  An in-memory shopping cart with per-item bulk discounts and order-level
  coupon stacking.

  Coupons are validated and recorded via `apply_coupon/2` and then applied,
  in order, at `calculate_totals/1` time.  A percentage coupon removes a
  fraction of the running amount; a fixed coupon removes a capped absolute
  amount that can never drive the running amount below zero.
  """

  @bulk_threshold 10
  @bulk_rate 0.10

  defmodule Item do
    @moduledoc "A single line item inside a `Cart`."
    @enforce_keys [:product_id, :quantity, :unit_price]
    defstruct [:product_id, :quantity, :unit_price]
  end

  @enforce_keys [:tax_rate, :items, :coupons]
  defstruct tax_rate: 0.0, items: %{}, coupons: []

  @doc "Creates a new, empty cart with an optional `:tax_rate`."
  @spec new(keyword()) :: %Cart{}
  def new(opts \\ []) do
    %Cart{tax_rate: Keyword.get(opts, :tax_rate, 0.0), items: %{}, coupons: []}
  end

  @doc "Adds `quantity` of `product_id`, summing existing quantities."
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
        items = Map.put(cart.items, product_id, %Item{item | quantity: quantity})
        {:ok, %Cart{cart | items: items}}
    end
  end

  def update_quantity(%Cart{}, _product_id, _quantity),
    do: {:error, :invalid_quantity}

  @doc """
  Validates and records `coupon` on the cart.

  Returns `{:ok, cart}` or one of `{:error, :invalid_coupon}`,
  `{:error, :already_applied}`, `{:error, :below_minimum}`.
  """
  @spec apply_coupon(%Cart{}, map()) ::
          {:ok, %Cart{}}
          | {:error, :invalid_coupon | :already_applied | :below_minimum}
  def apply_coupon(%Cart{} = cart, coupon) do
    with :ok <- validate_coupon(coupon),
         :ok <- ensure_not_applied(cart, coupon),
         :ok <- ensure_minimum(cart, coupon) do
      {:ok, %Cart{cart | coupons: cart.coupons ++ [normalize(coupon)]}}
    end
  end

  @doc "Computes the totals map, applying all recorded coupons in order."
  @spec calculate_totals(%Cart{}) :: %{
          subtotal: float(),
          discount: float(),
          discounted_subtotal: float(),
          tax: float(),
          grand_total: float(),
          coupons: [term()],
          items: [map()]
        }
  def calculate_totals(%Cart{} = cart) do
    items = cart.items |> Map.values() |> Enum.map(&build_summary/1)
    subtotal = Enum.reduce(items, 0.0, fn i, acc -> acc + i.line_total end)

    {discounted, discount} =
      Enum.reduce(cart.coupons, {subtotal, 0.0}, fn coupon, {running, disc} ->
        amount = coupon_amount(coupon, running)
        {running - amount, disc + amount}
      end)

    tax = discounted * cart.tax_rate

    %{
      items: items,
      subtotal: subtotal,
      discount: discount,
      discounted_subtotal: discounted,
      tax: tax,
      grand_total: discounted + tax,
      coupons: Enum.map(cart.coupons, & &1.code)
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_summary(%Item{} = item) do
    rate = if item.quantity >= @bulk_threshold, do: @bulk_rate, else: 0.0

    %{
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      discount_rate: rate,
      line_total: item.unit_price * (1.0 - rate) * item.quantity
    }
  end

  defp item_subtotal(%Cart{items: items}) do
    items
    |> Map.values()
    |> Enum.reduce(0.0, fn item, acc -> acc + build_summary(item).line_total end)
  end

  defp coupon_amount(%{type: :percentage, value: value}, running), do: running * value
  defp coupon_amount(%{type: :fixed, value: value}, running), do: min(value, running)

  defp validate_coupon(%{code: _code, type: type, value: value})
       when type in [:percentage, :fixed] and is_number(value) and value >= 0,
       do: :ok

  defp validate_coupon(_coupon), do: {:error, :invalid_coupon}

  defp ensure_not_applied(%Cart{coupons: coupons}, %{code: code}) do
    if Enum.any?(coupons, &(&1.code == code)),
      do: {:error, :already_applied},
      else: :ok
  end

  defp ensure_minimum(%Cart{} = cart, coupon) do
    minimum = Map.get(coupon, :min_subtotal, 0.0)
    if item_subtotal(cart) >= minimum, do: :ok, else: {:error, :below_minimum}
  end

  defp normalize(coupon) do
    %{
      code: coupon.code,
      type: coupon.type,
      value: coupon.value,
      min_subtotal: Map.get(coupon, :min_subtotal, 0.0)
    }
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    assert {:error, :invalid_coupon} = Cart.apply_coupon(cart, %{code: "Z", type: :bogus, value: 1})
    assert {:error, :invalid_coupon} = Cart.apply_coupon(cart, %{code: "Z", type: :fixed, value: -1})
  end

  test "no coupons means discount is zero" do
    # TODO
  end
end
```
