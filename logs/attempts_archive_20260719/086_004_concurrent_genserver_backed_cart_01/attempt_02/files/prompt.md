Write me an Elixir module called `CartServer` that implements a shopping cart as a **GenServer** — one process per cart — so that concurrent updates from many callers are serialized safely.

I need this public API (all client functions take the cart's `pid`):
- `CartServer.start_link(opts \\ [])` — starts a cart process and returns `{:ok, pid}`. Accepts a `:tax_rate` option (a float, e.g. `0.08`), defaulting to `0.0`.
- `CartServer.add_item(pid, product_id, quantity, unit_price)` — adds the quantity of a product at the unit price. If the product already exists, increase its quantity. Returns `:ok`, or `{:error, :invalid_quantity}` if quantity is not a positive integer.
- `CartServer.remove_item(pid, product_id)` — removes a product entirely and returns `:ok` (a no-op if absent).
- `CartServer.update_quantity(pid, product_id, quantity)` — sets the quantity of an existing item. If quantity is 0, remove the item and return `:ok`. If the product is not present, return `{:error, :not_found}`. If quantity is negative, return `{:error, :invalid_quantity}`. Otherwise return `:ok`.
- `CartServer.totals(pid)` — returns a map with:
  - `:subtotal` — sum of each item's `unit_price * quantity` after per-item discounts
  - `:tax` — `subtotal * tax_rate`
  - `:grand_total` — `subtotal + tax`
  - `:items` — a list of maps, one per cart item, each with `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`

Discount rule: a line item with quantity ≥ 10 gets a 10% discount on its unit price before its line total. Items below 10 receive no discount.

Because all state changes flow through the GenServer, concurrent `add_item` calls to the same product from many processes must accumulate correctly with no lost updates. All monetary values are floats. Give me the complete module in a single file with no external dependencies beyond OTP's `GenServer`.