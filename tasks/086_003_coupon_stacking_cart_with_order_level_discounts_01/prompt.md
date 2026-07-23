# Design brief: `Cart` — order-level coupon stacking over per-item bulk discounts

## Problem

We need an Elixir context module called `Cart` that implements an in-memory shopping cart with **order-level coupon stacking** layered on top of per-item bulk discounts. The existing per-item bulk discount behaviour stays as-is; the new capability is a stack of coupons applied to the order as a whole.

## Constraints

- The `Cart` struct must be a pure data structure — no database, no GenServer, no processes.
- All monetary values are floats.
- Deliver the complete module in a single file with no external dependencies.

## Required interface

The public API must consist of the following functions:

1. `Cart.new(opts \\ [])` — creates a new cart struct. Accepts a `:tax_rate` float (e.g. `0.08`), defaulting to `0.0`.

2. `Cart.add_item(cart, product_id, quantity, unit_price)` — adds the quantity of a product at the unit price, summing quantities for existing products. Reject with `{:error, :invalid_quantity}` if quantity is not a positive integer. Returns `{:ok, cart}`.

3. `Cart.remove_item(cart, product_id)` — removes a product entirely; a no-op if absent. Returns the updated cart struct directly (not wrapped in an `{:ok, _}` tuple).

4. `Cart.update_quantity(cart, product_id, quantity)` — sets an existing item's quantity. 0 removes it; unknown product returns `{:error, :not_found}`; negative returns `{:error, :invalid_quantity}`. Returns `{:ok, cart}`.

5. `Cart.apply_coupon(cart, coupon)` — records a coupon on the cart. A coupon is a map with keys `:code`, `:type` (`:percentage` or `:fixed`), `:value` (a non-negative number), and an optional `:min_subtotal` (defaulting to `0.0`). Validation:
   - If the coupon map is malformed (missing `:code`, unknown `:type`, or a non-number/negative `:value`), return `{:error, :invalid_coupon}`.
   - If a coupon with the same `:code` was already applied, return `{:error, :already_applied}`.
   - If the current item subtotal (after per-item discounts) is below the coupon's `:min_subtotal`, return `{:error, :below_minimum}`.
   - Otherwise return `{:ok, cart}` with the coupon appended (application order is preserved).

6. `Cart.calculate_totals(cart)` — returns a map with:
   - `:subtotal` — sum of item line totals after per-item bulk discounts (before coupons)
   - `:discount` — total amount removed by all coupons
   - `:discounted_subtotal` — `subtotal - discount`
   - `:tax` — `discounted_subtotal * tax_rate`
   - `:grand_total` — `discounted_subtotal + tax`
   - `:coupons` — the list of applied coupon codes, in application order
   - `:items` — a list of maps, one per item, each with `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`

## Acceptance criteria

- **Per-item discount rule** (unchanged from the base cart): a line item with quantity ≥ 10 gets a 10% discount on its unit price before its line total.
- **Coupon stacking rule**: coupons apply **sequentially in application order** against a running amount that starts at the item subtotal. A `:percentage` coupon removes `running * value`; a `:fixed` coupon removes `min(value, running)` (a fixed coupon can never push the running amount below zero). Because order matters, applying a percentage then a fixed coupon can differ from the reverse.
- All six functions above behave exactly as specified, including every error tuple and return-shape distinction.
