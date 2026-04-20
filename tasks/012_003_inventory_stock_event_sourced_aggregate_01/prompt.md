Write me an Elixir GenServer module called `InventoryAggregate` that maintains state through event sourcing for a product inventory domain.

I need these functions in the public API:

- `InventoryAggregate.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `InventoryAggregate.execute(server, id, command)` which validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. Commands are tuples: `{:register, product_name, sku}`, `{:receive_stock, quantity}`, `{:ship_stock, quantity}`, `{:adjust, quantity}`. If the command succeeds, return `{:ok, events}` where `events` is the list of new events produced by that command. If the command fails validation, return `{:error, reason}`.

- `InventoryAggregate.state(server, id)` which returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:name`, `:sku`, `:quantity_on_hand`, and `:status` keys (`:status` is `:registered` after registration).

- `InventoryAggregate.events(server, id)` which returns the full ordered list of events for that aggregate, oldest first.

The event sourcing logic should work as follows: each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, then they are appended to the event history. Events should be maps with at least a `:type` key. Use types like `:product_registered`, `:stock_received`, `:stock_shipped`, `:stock_adjusted`.

Validation rules:
- `:register` must fail with `{:error, :already_registered}` if the product is already registered.
- `:receive_stock` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity must be positive or fail with `{:error, :invalid_quantity}`.
- `:ship_stock` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity must be positive or fail with `{:error, :invalid_quantity}`. Must fail with `{:error, :insufficient_stock}` if quantity_on_hand is less than the shipment quantity.
- `:adjust` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity can be positive or negative but not zero — fail with `{:error, :invalid_quantity}` if zero. Must fail with `{:error, :insufficient_stock}` if a negative adjustment would bring quantity_on_hand below zero.

Each aggregate `id` must be tracked independently — commands on `"prod:1"` should have no effect on `"prod:2"`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.