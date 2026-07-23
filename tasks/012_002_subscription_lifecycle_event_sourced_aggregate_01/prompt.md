Hey — I need you to write me an Elixir GenServer module called `SubscriptionAggregate` that holds its state through event sourcing for a subscription management domain. Let me walk you through what I'm after.

For the public API, I need these functions. First, `SubscriptionAggregate.start_link(opts)` to start the process — it should accept a `:name` option for process registration.

Then `SubscriptionAggregate.execute(server, id, command)`, which validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. The commands come in as tuples: `{:create, plan_name}`, `{:activate}`, `{:suspend, reason}`, `{:cancel}`, `{:reactivate}`. When the command succeeds, I want you to return `{:ok, events}` where `events` is the list of new events produced by that command. When it fails validation, return `{:error, reason}` and produce no events.

I also need `SubscriptionAggregate.state(server, id)`, which returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:plan`, `:status`, and `:reason` keys — `:status` starts as `:pending` after creation, and `:reason` starts as `nil`.

And `SubscriptionAggregate.events(server, id)`, which returns the full ordered list of events for that aggregate, oldest first. If the aggregate has never received a successful command, return an empty list `[]`.

Here's how I want the event sourcing logic to flow: each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, then they're appended to the event history. Events should be maps with at least a `:type` key. Use types like `:subscription_created`, `:subscription_activated`, `:subscription_suspended`, `:subscription_cancelled`, `:subscription_reactivated`. The `:subscription_created` event must also carry a `:plan` key holding the plan name, and the `:subscription_suspended` event must also carry a `:reason` key holding the suspend reason.

Applying events should update the state like this:
- `:subscription_created` → `:plan` set to the plan name, `:status` set to `:pending`, `:reason` set to `nil`.
- `:subscription_activated` → `:status` set to `:active`.
- `:subscription_suspended` → `:status` set to `:suspended`, `:reason` set to the given reason.
- `:subscription_cancelled` → `:status` set to `:cancelled`, `:reason` reset to `nil`.
- `:subscription_reactivated` → `:status` set to `:active`, `:reason` reset to `nil`.

For validation, here are the rules I need enforced:
- `:create` must fail with `{:error, :already_exists}` if the subscription already exists (state is not nil).
- `:activate` must fail with `{:error, :not_found}` if the subscription hasn't been created, and must fail with `{:error, :not_pending}` if the status is not `:pending`.
- `:suspend` must fail with `{:error, :not_found}` if the subscription hasn't been created, and must fail with `{:error, :not_active}` if the status is not `:active`.
- `:cancel` must fail with `{:error, :not_found}` if the subscription hasn't been created, and must fail with `{:error, :already_cancelled}` if the status is already `:cancelled`. Cancelling should succeed from any other existing status (including `:pending`, `:active`, and `:suspended`).
- `:reactivate` must fail with `{:error, :not_found}` if the subscription hasn't been created, and must fail with `{:error, :not_cancelled}` if the status is not `:cancelled`.

One more thing that's important: each aggregate `id` must be tracked independently — commands on `"sub:1"` should have no effect on `"sub:2"`.

Please give me the complete module in a single file, and stick to OTP standard library only, no external dependencies.
