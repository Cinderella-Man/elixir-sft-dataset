Implement the private `validate_command/2` function. It is the command-validation
core of the event-sourcing pipeline: given the aggregate's current state (either
`nil` when the task does not yet exist, or a state map) and a command tuple, it must
return `{:ok, events}` — where `events` is a list of event maps (each with at least a
`:type` key) to be applied and persisted — or `{:error, reason}` when validation fails.

It must enforce these rules:

- `{:create, title, priority}`: valid only when the task does not exist yet (state is
  `nil`). If it already exists, fail with `{:error, :already_exists}`. If `priority` is
  not one of `:low`, `:medium`, `:high`, fail with `{:error, :invalid_priority}`. On
  success, produce a single `%{type: :task_created, title: title, priority: priority}`
  event.
- Any non-create command against a non-existent task (state `nil`) must fail with
  `{:error, :not_found}`.
- `{:assign, assignee}`: if the status is `:completed`, fail with
  `{:error, :already_completed}`. Otherwise produce
  `%{type: :task_assigned, assignee: assignee}`.
- `{:start}`: fail with `{:error, :not_assigned}` when the assignee is `nil`; fail with
  `{:error, :already_started}` when the status is already `:in_progress`. Otherwise
  produce `%{type: :task_started}`.
- `{:complete}`: succeed with `%{type: :task_completed}` only when the status is
  `:in_progress`; otherwise fail with `{:error, :not_in_progress}`.
- `{:reopen}`: succeed with `%{type: :task_reopened}` only when the status is
  `:completed`; otherwise fail with `{:error, :not_completed}`.

Implement it as a set of pattern-matched clauses so the validation reads declaratively.

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

  defp validate_command(state, command) do
    # TODO
  end

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