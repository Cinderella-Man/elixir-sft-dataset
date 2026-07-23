# Ticket: `Aggregate` — event-sourced bank account GenServer

Implement an Elixir GenServer module named `Aggregate` that maintains state via event sourcing for a simple bank account domain. Single file. OTP standard library only, no external dependencies.

**Public API**

- `Aggregate.start_link(opts)` — starts the process; must accept a `:name` option for process registration.
- `Aggregate.execute(server, id, command)` — validates `command` against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. Returns `{:ok, events}` on success, where `events` is the list of new events produced by that command. Returns `{:error, reason}` on validation failure.
- `Aggregate.state(server, id)` — returns the current state of the aggregate. Returns `nil` if the aggregate has never received a command. Otherwise returns a map with at least `:name`, `:balance`, and `:status` keys (`:status` is `:open` after opening).
- `Aggregate.events(server, id)` — returns the full ordered list of events for that aggregate, oldest first. Returns an empty list if the aggregate has never received a command.

**Commands** (tuples)

- `{:open, account_name}`
- `{:deposit, amount}`
- `{:withdraw, amount}`

**Event-sourcing flow** (per command)

- Validate the command against the current state.
- Produce zero or more event structs/maps.
- Apply the events one by one to the state.
- Append the events to the event history.

**Events**

- Events are maps with at least a `:type` key.
- Use types `:account_opened`, `:amount_deposited`, `:amount_withdrawn`.
- `:account_opened` must include the account name under a `:name` (or `:account_name`) key.
- `:amount_deposited` and `:amount_withdrawn` must include the amount under an `:amount` key.

**Validation — `:open`**

- Fail with `{:error, :already_open}` if the account is already open.

**Validation — `:deposit`**

- Fail with `{:error, :account_not_open}` if the account hasn't been opened yet.
- Amount must be positive, else `{:error, :invalid_amount}`.

**Validation — `:withdraw`**

- Fail with `{:error, :account_not_open}` if the account hasn't been opened.
- Amount must be positive, else `{:error, :invalid_amount}`.
- Fail with `{:error, :insufficient_balance}` if the balance is less than the withdrawal amount.
- Withdrawing exactly the current balance succeeds and leaves the balance at zero.

**Isolation**

- Each aggregate `id` is tracked independently — commands on `"acct:1"` must have no effect on `"acct:2"`.
