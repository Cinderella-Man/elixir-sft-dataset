# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `TaskAggregate` that maintains state through event sourcing for a task/issue tracking domain.

I need these functions in the public API:

- `TaskAggregate.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `TaskAggregate.execute(server, id, command)` which validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. Commands are tuples: `{:create, title, priority}` where priority is `:low`, `:medium`, or `:high`; `{:assign, assignee_name}`; `{:start}`; `{:complete}`; `{:reopen}`. If the command succeeds, return `{:ok, events}` where `events` is the list of new events produced by that command. If the command fails validation, return `{:error, reason}`.

- `TaskAggregate.state(server, id)` which returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:title`, `:assignee`, `:status`, and `:priority` keys (`:status` starts as `:created` after creation, `:assignee` starts as `nil`).

- `TaskAggregate.events(server, id)` which returns the full ordered list of events for that aggregate, oldest first. If the aggregate has never received a command, return an empty list.

The event sourcing logic should work as follows: each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, then they are appended to the event history. Events should be maps with at least a `:type` key. Use types like `:task_created`, `:task_assigned`, `:task_started`, `:task_completed`, `:task_reopened`. In addition to `:type`, the `:task_created` event must carry the title and priority under `:title` and `:priority` keys, and the `:task_assigned` event must carry the assignee name under an `:assignee` key.

Validation rules:
- `:create` must fail with `{:error, :already_exists}` if the task already exists. Priority must be one of `:low`, `:medium`, `:high` — otherwise fail with `{:error, :invalid_priority}`.
- `:assign` must fail with `{:error, :not_found}` if the task hasn't been created. Must fail with `{:error, :already_completed}` if the status is `:completed`.
- `:start` must fail with `{:error, :not_found}` if the task hasn't been created. Must fail with `{:error, :not_assigned}` if the task has no assignee (assignee is nil). Must fail with `{:error, :already_started}` if the status is already `:in_progress`.
- `:complete` must fail with `{:error, :not_found}` if the task hasn't been created. Must fail with `{:error, :not_in_progress}` if the status is not `:in_progress`.
- `:reopen` must fail with `{:error, :not_found}` if the task hasn't been created. Must fail with `{:error, :not_completed}` if the status is not `:completed`. Reopening resets status to `:created` and clears the assignee to `nil`.

Each aggregate `id` must be tracked independently — commands on `"task:1"` should have no effect on `"task:2"`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `start_link` missing

```elixir
defmodule TaskAggregate do
  @moduledoc """
  An event-sourced Aggregate for a task/issue tracking domain.
  Maintains independent state and event history for multiple task IDs.
  """

  use GenServer

  @valid_priorities [:low, :medium, :high]

  @type id :: any()
  @type command ::
          {:create, String.t(), atom()}
          | {:assign, String.t()}
          | {:start}
          | {:complete}
          | {:reopen}
  @type event :: %{atom() => any(), type: atom()}
  @type state_map ::
          %{
            title: String.t(),
            assignee: String.t() | nil,
            status: atom(),
            priority: atom()
          }
          | nil

  # --- Public API ---

  def start_link(opts \\ []) do
    # TODO
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

  defp validate_command(nil, {:create, title, priority}) do
    if priority in @valid_priorities do
      {:ok, [%{type: :task_created, title: title, priority: priority}]}
    else
      {:error, :invalid_priority}
    end
  end

  defp validate_command(_state, {:create, _title, _priority}), do: {:error, :already_exists}

  defp validate_command(nil, _command), do: {:error, :not_found}

  defp validate_command(%{status: :completed}, {:assign, _assignee}),
    do: {:error, :already_completed}

  defp validate_command(_state, {:assign, assignee}) do
    {:ok, [%{type: :task_assigned, assignee: assignee}]}
  end

  defp validate_command(%{assignee: nil}, {:start}), do: {:error, :not_assigned}
  defp validate_command(%{status: :in_progress}, {:start}), do: {:error, :already_started}

  defp validate_command(_state, {:start}) do
    {:ok, [%{type: :task_started}]}
  end

  defp validate_command(%{status: :in_progress}, {:complete}) do
    {:ok, [%{type: :task_completed}]}
  end

  defp validate_command(_state, {:complete}), do: {:error, :not_in_progress}

  defp validate_command(%{status: :completed}, {:reopen}) do
    {:ok, [%{type: :task_reopened}]}
  end

  defp validate_command(_state, {:reopen}), do: {:error, :not_completed}

  # --- Domain Logic: Event Application ---

  defp apply_event(%{type: :task_created, title: title, priority: priority}, _nil_state) do
    %{title: title, assignee: nil, status: :created, priority: priority}
  end

  defp apply_event(%{type: :task_assigned, assignee: assignee}, state) do
    %{state | assignee: assignee}
  end

  defp apply_event(%{type: :task_started}, state) do
    %{state | status: :in_progress}
  end

  defp apply_event(%{type: :task_completed}, state) do
    %{state | status: :completed}
  end

  defp apply_event(%{type: :task_reopened}, state) do
    %{state | status: :created, assignee: nil}
  end
end
```

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
