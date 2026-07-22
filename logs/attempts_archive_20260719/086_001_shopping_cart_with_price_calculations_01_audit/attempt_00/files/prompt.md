Write me an Elixir context module called `Cart` that implements an in-memory shopping cart with price calculations.

I need these functions in the public API:
- `Cart.new(opts \\ [])` to create a new cart struct. It should accept a `:tax_rate` option as a float (e.g. `0.08` for 8%). If not provided, default to `0.0`.
- `Cart.add_item(cart, product_id, quantity, unit_price)` which adds the given quantity of a product at the given unit price. If the product already exists in the cart, increase its quantity. Reject with `{:error, :invalid_quantity}` if quantity is not a positive integer.
- `Cart.remove_item(cart, product_id)` which removes a product entirely from the cart. If the product is not in the cart, return the cart unchanged.
- `Cart.update_quantity(cart, product_id, quantity)` which sets the quantity of an existing item. If quantity is 0, remove the item entirely. If the product is not in the cart, return `{:error, :not_found}`. Reject with `{:error, :invalid_quantity}` if quantity is negative.
- `Cart.calculate_totals(cart)` which returns a map with the following keys:
  - `:subtotal` — sum of each item's `unit_price * quantity` after per-item discounts
  - `:tax` — `subtotal * tax_rate`
  - `:grand_total` — `subtotal + tax`
  - `:items` — a list of maps, one per cart item, each containing `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`

The discount rule is: if a single line item has a quantity of 10 or more, that item gets a 10% discount applied to its unit price before computing the line total. Items with quantity below 10 receive no discount.

The `Cart` struct must be a pure data structure with no database, no GenServer, and no processes — just plain Elixir structs and functions. All monetary values are floats. Give me the complete module in a single file with no external dependencies.

## Additional interface contract

- The cart returned by `Cart.new/1` is a struct with public fields `:tax_rate` and `:items`: `:tax_rate` holds the configured tax rate (`0.0` by default), and `:items` is a map keyed by product id that is `%{}` for a new, empty cart.
- In the map returned by `calculate_totals/1`, `:items` is a flat list with exactly one entry per distinct product (an empty cart yields `[]`), and each entry is a plain map whose `:product_id`, `:quantity`, and `:unit_price` echo the values accumulated via `add_item` — e.g. after `add_item(cart, "prod:1", 2, 5.0)` the sole entry satisfies `product_id == "prod:1"`, `quantity == 2`, and `unit_price == 5.0` (the raw per-unit price, not the discounted price or line total).
- On success, `add_item/4` returns `{:ok, updated_cart}` — never the bare cart struct. `update_quantity/3` likewise returns `{:ok, updated_cart}` on every success path, including when the quantity is `0` and the item is removed.
- `remove_item/2` is the exception: it returns the updated cart struct directly, NOT wrapped in an `{:ok, _}` tuple — including the no-op case where the product id is unknown — because callers pass its result straight into `calculate_totals/1`.
- Each item entry's `:discount_rate` is compared with exact `==`: it must be exactly `0.1` for a discounted line (quantity of 10 or more) and exactly `0.0` otherwise — a fraction, not a percentage such as `10.0`.
- All monetary outputs are plain floats computed with ordinary float arithmetic (no `Decimal`); totals are asserted to within `±0.001`, so no rounding step is required.