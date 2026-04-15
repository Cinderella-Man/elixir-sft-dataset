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