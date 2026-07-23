# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule Aggregate do
  @moduledoc """
  An event-sourced Aggregate for a simple bank account domain.
  Maintains independent state and event history for multiple account IDs.
  """

  use GenServer

  @type id :: any()
  @type command :: {:open, String.t()} | {:deposit, number()} | {:withdraw, number()}
  @type event :: %{atom() => any(), type: atom()}
  @type state_map :: %{name: String.t(), balance: number(), status: :open} | nil

  # --- Public API ---

  @doc "Starts the GenServer process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc "Validates a command, produces events, updates state, and persists history."
  @spec execute(GenServer.server(), id(), command()) :: {:ok, [event()]} | {:error, atom()}
  def execute(server, id, command) do
    GenServer.call(server, {:execute, id, command})
  end

  @doc "Returns the current calculated state for a specific aggregate ID."
  @spec state(GenServer.server(), id()) :: state_map()
  def state(server, id) do
    GenServer.call(server, {:get_state, id})
  end

  @doc "Returns the full history of events for a specific aggregate ID."
  @spec events(GenServer.server(), id()) :: [event()]
  def events(server, id) do
    GenServer.call(server, {:get_events, id})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(initial_state), do: {:ok, initial_state}

  @impl true
  def handle_call({:execute, id, command}, _from, store) do
    current_instance = Map.get(store, id, %{state: nil, events: []})

    case validate_command(current_instance.state, command) do
      {:ok, new_events} ->
        updated_state = Enum.reduce(new_events, current_instance.state, &apply_event/2)

        updated_instance = %{
          state: updated_state,
          events: current_instance.events ++ new_events
        }

        {:reply, {:ok, new_events}, Map.put(store, id, updated_instance)}

      {:error, reason} ->
        {:reply, {:error, reason}, store}
    end
  end

  @impl true
  def handle_call({:get_state, id}, _from, store) do
    {:reply, get_in(store, [id, :state]), store}
  end

  @impl true
  def handle_call({:get_events, id}, _from, store) do
    history =
      store
      |> Map.get(id, %{})
      |> Map.get(:events, [])

    {:reply, history, store}
  end

  # --- Domain Logic: Command Validation ---

  defp validate_command(nil, {:open, name}) do
    {:ok, [%{type: :account_opened, name: name}]}
  end

  defp validate_command(_state, {:open, _name}), do: {:error, :already_open}

  defp validate_command(nil, _command), do: {:error, :account_not_open}

  defp validate_command(_state, {:deposit, amount}) do
    cond do
      amount <= 0 -> {:error, :invalid_amount}
      true -> {:ok, [%{type: :amount_deposited, amount: amount}]}
    end
  end

  defp validate_command(state, {:withdraw, amount}) do
    cond do
      amount <= 0 -> {:error, :invalid_amount}
      state.balance < amount -> {:error, :insufficient_balance}
      true -> {:ok, [%{type: :amount_withdrawn, amount: amount}]}
    end
  end

  # --- Domain Logic: Event Application ---

  defp apply_event(%{type: :account_opened, name: name}, _nil_state) do
    %{name: name, balance: 0, status: :open}
  end

  defp apply_event(%{type: :amount_deposited, amount: amount}, state) do
    %{state | balance: state.balance + amount}
  end

  defp apply_event(%{type: :amount_withdrawn, amount: amount}, state) do
    %{state | balance: state.balance - amount}
  end
end
```

## New specification

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
