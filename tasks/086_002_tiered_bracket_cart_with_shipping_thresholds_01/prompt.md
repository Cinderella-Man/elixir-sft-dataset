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
