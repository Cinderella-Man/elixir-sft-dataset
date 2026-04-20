Write me an Elixir GenServer module called `SubscriptionAggregate` that maintains state through event sourcing for a subscription management domain.

I need these functions in the public API:

- `SubscriptionAggregate.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `SubscriptionAggregate.execute(server, id, command)` which validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. Commands are tuples: `{:create, plan_name}`, `{:activate}`, `{:suspend, reason}`, `{:cancel}`, `{:reactivate}`. If the command succeeds, return `{:ok, events}` where `events` is the list of new events produced by that command. If the command fails validation, return `{:error, reason}`.

- `SubscriptionAggregate.state(server, id)` which returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:plan`, `:status`, and `:reason` keys (`:status` starts as `:pending` after creation).

- `SubscriptionAggregate.events(server, id)` which returns the full ordered list of events for that aggregate, oldest first.

The event sourcing logic should work as follows: each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, then they are appended to the event history. Events should be maps with at least a `:type` key. Use types like `:subscription_created`, `:subscription_activated`, `:subscription_suspended`, `:subscription_cancelled`, `:subscription_reactivated`.

Validation rules:
- `:create` must fail with `{:error, :already_exists}` if the subscription already exists (state is not nil).
- `:activate` must fail with `{:error, :not_found}` if the subscription hasn't been created. Must fail with `{:error, :not_pending}` if the status is not `:pending`.
- `:suspend` must fail with `{:error, :not_found}` if the subscription hasn't been created. Must fail with `{:error, :not_active}` if the status is not `:active`.
- `:cancel` must fail with `{:error, :not_found}` if the subscription hasn't been created. Must fail with `{:error, :already_cancelled}` if the status is already `:cancelled`.
- `:reactivate` must fail with `{:error, :not_found}` if the subscription hasn't been created. Must fail with `{:error, :not_cancelled}` if the status is not `:cancelled`.

Each aggregate `id` must be tracked independently — commands on `"sub:1"` should have no effect on `"sub:2"`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.