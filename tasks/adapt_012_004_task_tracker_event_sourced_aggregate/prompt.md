# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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
