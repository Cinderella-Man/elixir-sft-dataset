Write me an Elixir GenServer module called `Aggregate` that maintains state through event sourcing for a simple bank account domain.

I need these functions in the public API:

- `Aggregate.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `Aggregate.execute(server, id, command)` which validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. Commands are tuples: `{:open, account_name}`, `{:deposit, amount}`, `{:withdraw, amount}`. If the command succeeds, return `{:ok, events}` where `events` is the list of new events produced by that command. If the command fails validation, return `{:error, reason}`.

- `Aggregate.state(server, id)` which returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:name`, `:balance`, and `:status` keys (`:status` is `:open` after opening).

- `Aggregate.events(server, id)` which returns the full ordered list of events for that aggregate, oldest first.

The event sourcing logic should work as follows: each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, then they are appended to the event history. Events should be maps with at least a `:type` key. Use types like `:account_opened`, `:amount_deposited`, `:amount_withdrawn`.

Validation rules:
- `:open` must fail with `{:error, :already_open}` if the account is already open.
- `:deposit` must fail with `{:error, :account_not_open}` if the account hasn't been opened yet. Amount must be positive or fail with `{:error, :invalid_amount}`.
- `:withdraw` must fail with `{:error, :account_not_open}` if the account hasn't been opened. Amount must be positive or fail with `{:error, :invalid_amount}`. Must fail with `{:error, :insufficient_balance}` if the balance is less than the withdrawal amount.

Each aggregate `id` must be tracked independently — commands on `"acct:1"` should have no effect on `"acct:2"`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.