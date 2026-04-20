Write me an Elixir GenServer module called `TaskAggregate` that maintains state through event sourcing for a task/issue tracking domain.

I need these functions in the public API:

- `TaskAggregate.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `TaskAggregate.execute(server, id, command)` which validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. Commands are tuples: `{:create, title, priority}` where priority is `:low`, `:medium`, or `:high`; `{:assign, assignee_name}`; `{:start}`; `{:complete}`; `{:reopen}`. If the command succeeds, return `{:ok, events}` where `events` is the list of new events produced by that command. If the command fails validation, return `{:error, reason}`.

- `TaskAggregate.state(server, id)` which returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:title`, `:assignee`, `:status`, and `:priority` keys (`:status` starts as `:created` after creation, `:assignee` starts as `nil`).

- `TaskAggregate.events(server, id)` which returns the full ordered list of events for that aggregate, oldest first.

The event sourcing logic should work as follows: each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, then they are appended to the event history. Events should be maps with at least a `:type` key. Use types like `:task_created`, `:task_assigned`, `:task_started`, `:task_completed`, `:task_reopened`.

Validation rules:
- `:create` must fail with `{:error, :already_exists}` if the task already exists. Priority must be one of `:low`, `:medium`, `:high` — otherwise fail with `{:error, :invalid_priority}`.
- `:assign` must fail with `{:error, :not_found}` if the task hasn't been created. Must fail with `{:error, :already_completed}` if the status is `:completed`.
- `:start` must fail with `{:error, :not_found}` if the task hasn't been created. Must fail with `{:error, :not_assigned}` if the task has no assignee (assignee is nil). Must fail with `{:error, :already_started}` if the status is already `:in_progress`.
- `:complete` must fail with `{:error, :not_found}` if the task hasn't been created. Must fail with `{:error, :not_in_progress}` if the status is not `:in_progress`.
- `:reopen` must fail with `{:error, :not_found}` if the task hasn't been created. Must fail with `{:error, :not_completed}` if the status is not `:completed`. Reopening resets status to `:created` and clears the assignee to `nil`.

Each aggregate `id` must be tracked independently — commands on `"task:1"` should have no effect on `"task:2"`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.