# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Specification: `Cart` — Tiered Bracket Cart with Shipping Thresholds

## Overview

This document specifies an Elixir context module called `Cart` that implements an in-memory shopping cart with **tiered bulk-discount brackets** and **shipping-threshold** logic.

The `Cart` struct must be a pure data structure — no database, no GenServer, no processes. All monetary values are floats. The deliverable is the complete module in a single file with no external dependencies.

## API

The following functions make up the public API.

### `Cart.new(opts \\ [])`

Creates a new cart struct. It should accept:

- `:tax_rate` — a float (e.g. `0.08` for 8%). Defaults to `0.0`.
- `:discount_tiers` — a list of `{min_quantity, rate}` tuples describing per-line quantity brackets. Defaults to `[{10, 0.05}, {25, 0.10}, {50, 0.15}]`.
- `:shipping_flat` — a flat shipping cost (float) added to the order. Defaults to `0.0`.
- `:free_shipping_threshold` — if the discounted subtotal is greater than or equal to this value, shipping is waived. Defaults to `nil` (never waived automatically).

### `Cart.add_item(cart, product_id, quantity, unit_price)`

Adds the given quantity of a product at the given unit price. If the product already exists, its quantity is increased. Rejects with `{:error, :invalid_quantity}` if quantity is not a positive integer. Returns `{:ok, cart}` on success.

### `Cart.remove_item(cart, product_id)`

Removes a product entirely. If the product is not present, the cart is returned unchanged.

### `Cart.update_quantity(cart, product_id, quantity)`

Sets the quantity of an existing item. If quantity is 0, the item is removed. If the product is not in the cart, returns `{:error, :not_found}`. Rejects with `{:error, :invalid_quantity}` if quantity is negative. Returns `{:ok, cart}` on success.

### `Cart.calculate_totals(cart)`

Returns a map with:

- `:subtotal` — sum of each item's line total after its bracket discount
- `:tax` — `subtotal * tax_rate` (tax is charged on the discounted subtotal only, NOT on shipping)
- `:shipping` — the shipping cost for this order (see rules below)
- `:grand_total` — `subtotal + tax + shipping`
- `:items` — a list of maps, one per cart item, each with `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`

## Calculation rules

**Bracket discount rule:** for each line item, the **highest applicable tier** is chosen — the tier with the largest `min_quantity` that is less than or equal to the line's quantity. That tier's rate is applied to the unit price before computing the line total.

**Shipping rule:** if `:free_shipping_threshold` is a number and the discounted subtotal is greater than or equal to it, shipping is `0.0`; otherwise shipping is `:shipping_flat`.

## Struct / interface contract

The cart returned by `Cart.new/1` is a struct whose configuration is exposed as public fields matching the options above — `:tax_rate`, `:discount_tiers`, `:shipping_flat`, and `:free_shipping_threshold` hold the configured (or default) values — plus an `:items` field, a map keyed by product id.

## Edge cases

- If no tier applies to a line item, the discount rate is `0.0`.
- If the cart has **no items**, shipping is `0.0` (this takes precedence over the threshold and flat-cost rules).
- The `:items` field is `%{}` for a new, empty cart.
- `Cart.add_item/4` with a quantity that is not a positive integer returns `{:error, :invalid_quantity}`.
- `Cart.update_quantity/3` with a quantity of 0 removes the item; with a negative quantity it returns `{:error, :invalid_quantity}`; for a product not in the cart it returns `{:error, :not_found}`.
- `Cart.remove_item/2` on a product that is not present returns the cart unchanged.

## The buggy module

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

  @default_tiers [{11, 0.05}, {25, 0.10}, {50, 0.15}]

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

## Failing test report

```
2 of 8 test(s) failed:

  * test new/0 uses defaults
      
      
      Assertion with == failed
      code:  assert cart.discount_tiers == [{10, 0.05}, {25, 0.1}, {50, 0.15}]
      left:  [{11, 0.05}, {25, 0.1}, {50, 0.15}]
      right: [{10, 0.05}, {25, 0.1}, {50, 0.15}]
      

  * test bracket tiers pick the highest applicable rate
      
      
      Assertion with == failed
      code:  assert b.discount_rate == 0.05
      left:  0.0
      right: 0.05
```
