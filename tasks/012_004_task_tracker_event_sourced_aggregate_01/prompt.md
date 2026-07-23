# Ticket: `TaskAggregate` — event-sourced task/issue tracker aggregate

Implement an Elixir GenServer module `TaskAggregate` that maintains state via event sourcing for a task/issue tracking domain. Deliver the complete module in a single file. OTP standard library only — no external dependencies.

**Public API**

- `TaskAggregate.start_link(opts)` — starts the process. Accepts a `:name` option for process registration.
- `TaskAggregate.execute(server, id, command)` — validates `command` against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. On success return `{:ok, events}` where `events` is the list of new events produced by that command. On failed validation return `{:error, reason}`.
- `TaskAggregate.state(server, id)` — returns the current state of the aggregate. Return `nil` if the aggregate has never received a command. Otherwise return a map with at least `:title`, `:assignee`, `:status`, and `:priority` keys. `:status` starts as `:created` after creation; `:assignee` starts as `nil`.
- `TaskAggregate.events(server, id)` — returns the full ordered event list for that aggregate, oldest first. Return an empty list if the aggregate has never received a command.

**Commands** (tuples)

- `{:create, title, priority}` — priority is `:low`, `:medium`, or `:high`.
- `{:assign, assignee_name}`
- `{:start}`
- `{:complete}`
- `{:reopen}`

**Event-sourcing flow**

- Each command is first validated against the current state, then zero or more event structs/maps are produced, then applied one by one to the state, then appended to the event history.
- Events are maps with at least a `:type` key. Use types `:task_created`, `:task_assigned`, `:task_started`, `:task_completed`, `:task_reopened`.
- Beyond `:type`, the `:task_created` event must carry the title and priority under `:title` and `:priority` keys.
- Beyond `:type`, the `:task_assigned` event must carry the assignee name under an `:assignee` key.

**Validation — `:create`**

- Fail with `{:error, :already_exists}` if the task already exists.
- Priority must be one of `:low`, `:medium`, `:high` — otherwise fail with `{:error, :invalid_priority}`.

**Validation — `:assign`**

- Fail with `{:error, :not_found}` if the task hasn't been created.
- Fail with `{:error, :already_completed}` if the status is `:completed`.

**Validation — `:start`**

- Fail with `{:error, :not_found}` if the task hasn't been created.
- Fail with `{:error, :not_assigned}` if the task has no assignee (assignee is nil).
- Fail with `{:error, :already_started}` if the status is already `:in_progress`.

**Validation — `:complete`**

- Fail with `{:error, :not_found}` if the task hasn't been created.
- Fail with `{:error, :not_in_progress}` if the status is not `:in_progress`.

**Validation — `:reopen`**

- Fail with `{:error, :not_found}` if the task hasn't been created.
- Fail with `{:error, :not_completed}` if the status is not `:completed`.
- Reopening resets status to `:created` and clears the assignee to `nil`.

**Isolation**

- Each aggregate `id` must be tracked independently — commands on `"task:1"` must have no effect on `"task:2"`.
