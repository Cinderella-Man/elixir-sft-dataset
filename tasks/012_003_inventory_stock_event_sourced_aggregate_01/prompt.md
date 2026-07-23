# Design brief: `InventoryAggregate`

## Problem

Build an Elixir GenServer module called `InventoryAggregate` that maintains its state through event sourcing for a product inventory domain. Each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, and finally they are appended to the event history.

## Constraints

- Deliver the complete module in a single file.
- Use only the OTP standard library — no external dependencies.
- Each aggregate `id` must be tracked independently: commands on `"prod:1"` should have no effect on `"prod:2"`.
- Commands are tuples: `{:register, product_name, sku}`, `{:receive_stock, quantity}`, `{:ship_stock, quantity}`, `{:adjust, quantity}`.
- Events are maps carrying at least a `:type` key. Use the types `:product_registered`, `:stock_received`, `:stock_shipped`, `:stock_adjusted`. Beyond `:type`, each event must carry the data relevant to it:
  - the `:product_registered` event must include the product name (under `:name` or `:product_name`) and the `:sku`;
  - the `:stock_received`, `:stock_shipped`, and `:stock_adjusted` events must each include a `:quantity` key holding the command's quantity — the signed value for adjustments (e.g. `-20` for `{:adjust, -20}`).

## Required interface

1. `InventoryAggregate.start_link(opts)` — starts the process. It should accept a `:name` option for process registration.

2. `InventoryAggregate.execute(server, id, command)` — validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. If the command succeeds, return `{:ok, events}` where `events` is the list of new events produced by that command. If the command fails validation, return `{:error, reason}`.

3. `InventoryAggregate.state(server, id)` — returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:name`, `:sku`, `:quantity_on_hand`, and `:status` keys (`:status` is `:registered` after registration).

4. `InventoryAggregate.events(server, id)` — returns the full ordered list of events for that aggregate, oldest first.

## Acceptance criteria

Validation rules that must hold:

- `:register` must fail with `{:error, :already_registered}` if the product is already registered.
- `:receive_stock` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity must be positive or fail with `{:error, :invalid_quantity}`.
- `:ship_stock` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity must be positive or fail with `{:error, :invalid_quantity}`. Must fail with `{:error, :insufficient_stock}` if quantity_on_hand is less than the shipment quantity.
- `:adjust` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity can be positive or negative but not zero — fail with `{:error, :invalid_quantity}` if zero. Must fail with `{:error, :insufficient_stock}` if a negative adjustment would bring quantity_on_hand below zero.
