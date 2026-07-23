I need a shopping cart backed by a GenServer and I'd like you to write it for me. Call the module `CartServer`. The idea is one process per cart, so that when a bunch of callers hammer the same cart concurrently, the updates get serialized safely instead of stepping on each other.

Here's the public API I'm after — every client function takes the cart's `pid`:

`CartServer.start_link(opts \\ [])` starts a cart process and hands back `{:ok, pid}`. It should accept a `:tax_rate` option (a float, e.g. `0.08`), and when nobody passes one it defaults to `0.0`.

`CartServer.add_item(pid, product_id, quantity, unit_price)` adds the given quantity of a product at the given unit price. If that product is already in the cart, bump its quantity rather than duplicating the line. It returns `:ok`, or `{:error, :invalid_quantity}` when quantity isn't a positive integer — and in that error case I want the cart left exactly as it was, no partial mutation.

`CartServer.remove_item(pid, product_id)` drops a product entirely and returns `:ok`. If the product isn't there, it's just a no-op (still `:ok`).

`CartServer.update_quantity(pid, product_id, quantity)` sets the quantity of an item that already exists. A quantity of 0 means remove the item and return `:ok`. If the product isn't present at all, return `{:error, :not_found}`. If the quantity is negative, return `{:error, :invalid_quantity}`. Anything else, return `:ok`.

`CartServer.totals(pid)` gives me back a map containing `:subtotal` — the sum over items of `unit_price * quantity` after per-item discounts are applied; `:tax` — that's `subtotal * tax_rate`; `:grand_total` — `subtotal + tax`; and `:items` — a list of maps, one per cart item, each carrying `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`. I want `:discount_rate` expressed as a fraction: `0.1` when the bulk discount kicks in, otherwise `0.0`. For an empty cart, `:items` should come back as `[]` and `:subtotal`, `:tax`, and `:grand_total` should each be `0.0`.

The discount rule itself: any line item with quantity ≥ 10 gets a 10% discount applied to its unit price before the line total is computed. Items under 10 get no discount.

Since every state change funnels through the GenServer, concurrent `add_item` calls against the same product from many processes have to accumulate correctly with zero lost updates — that's really the point of the exercise. All monetary values are floats. Please give me the complete module in a single file, with no external dependencies beyond OTP's `GenServer`.
