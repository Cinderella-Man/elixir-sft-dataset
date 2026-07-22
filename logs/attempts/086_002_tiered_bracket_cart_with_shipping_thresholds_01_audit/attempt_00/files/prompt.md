Write me an Elixir context module called `Cart` that implements an in-memory shopping cart with **tiered bulk-discount brackets** and **shipping-threshold** logic.

I need these functions in the public API:
- `Cart.new(opts \\ [])` to create a new cart struct. It should accept:
  - `:tax_rate` — a float (e.g. `0.08` for 8%). Defaults to `0.0`.
  - `:discount_tiers` — a list of `{min_quantity, rate}` tuples describing per-line quantity brackets. Defaults to `[{10, 0.05}, {25, 0.10}, {50, 0.15}]`.
  - `:shipping_flat` — a flat shipping cost (float) added to the order. Defaults to `0.0`.
  - `:free_shipping_threshold` — if the discounted subtotal is greater than or equal to this value, shipping is waived. Defaults to `nil` (never waived automatically).
- `Cart.add_item(cart, product_id, quantity, unit_price)` which adds the given quantity of a product at the given unit price. If the product already exists, increase its quantity. Reject with `{:error, :invalid_quantity}` if quantity is not a positive integer. Returns `{:ok, cart}` on success.
- `Cart.remove_item(cart, product_id)` which removes a product entirely. If the product is not present, return the cart unchanged.
- `Cart.update_quantity(cart, product_id, quantity)` which sets the quantity of an existing item. If quantity is 0, remove the item. If the product is not in the cart, return `{:error, :not_found}`. Reject with `{:error, :invalid_quantity}` if quantity is negative. Returns `{:ok, cart}` on success.
- `Cart.calculate_totals(cart)` which returns a map with:
  - `:subtotal` — sum of each item's line total after its bracket discount
  - `:tax` — `subtotal * tax_rate` (tax is charged on the discounted subtotal only, NOT on shipping)
  - `:shipping` — the shipping cost for this order (see rules below)
  - `:grand_total` — `subtotal + tax + shipping`
  - `:items` — a list of maps, one per cart item, each with `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`

Bracket discount rule: for each line item, choose the **highest applicable tier** — the tier with the largest `min_quantity` that is less than or equal to the line's quantity. Apply that tier's rate to the unit price before computing the line total. If no tier applies, the discount rate is `0.0`.

Shipping rule: if the cart has **no items**, shipping is `0.0`. Otherwise, if `:free_shipping_threshold` is a number and the discounted subtotal is greater than or equal to it, shipping is `0.0`; otherwise shipping is `:shipping_flat`.

The `Cart` struct must be a pure data structure — no database, no GenServer, no processes. All monetary values are floats. Give me the complete module in a single file with no external dependencies.

## Additional interface contract

- The cart returned by `Cart.new/1` is a struct whose configuration is exposed as public fields matching the options above — `:tax_rate`, `:discount_tiers`, `:shipping_flat`, and `:free_shipping_threshold` hold the configured (or default) values — plus an `:items` field, a map keyed by product id that is `%{}` for a new, empty cart.