Implement the private `validate_command/2` function. It is the command-validation
core of the event-sourced aggregate: given the aggregate's `current_state` (a map
with `:plan`, `:status`, and `:reason`, or `nil` if the subscription has never been
created) and a `command` tuple, it must decide whether the command is legal and, if
so, produce the list of new events it generates. On success it returns
`{:ok, events}` where `events` is a list of event maps (each with at least a `:type`
key); on failure it returns `{:error, reason}`.

The rules it must enforce:

- `{:create, plan_name}` — succeeds only when the aggregate does not yet exist
  (`current_state` is `nil`), producing `[%{type: :subscription_created, plan: plan_name}]`.
  If the aggregate already exists, fail with `{:error, :already_exists}`.
- For every non-`:create` command, if the aggregate has never been created
  (`current_state` is `nil`), fail with `{:error, :not_found}`.
- `{:activate}` — succeeds only when the status is `:pending`, producing
  `[%{type: :subscription_activated}]`. Otherwise fail with `{:error, :not_pending}`.
- `{:suspend, reason}` — succeeds only when the status is `:active`, producing
  `[%{type: :subscription_suspended, reason: reason}]`. Otherwise fail with
  `{:error, :not_active}`.
- `{:cancel}` — fails with `{:error, :already_cancelled}` when the status is already
  `:cancelled`, and fails with `{:error, :not_active}` when the status is `:pending`
  (a subscription that was never activated cannot be cancelled). For any other status
  (`:active` or `:suspended`) it succeeds, producing `[%{type: :subscription_cancelled}]`.
- `{:reactivate}` — succeeds only when the status is `:cancelled`, producing
  `[%{type: :subscription_reactivated}]`. Otherwise fail with `{:error, :not_cancelled}`.

Implement it as a set of `defp validate_command/2` clauses that pattern-match on the
state and the command.

```elixir
defmodule SubscriptionAggregate do
  @moduledoc """
  An event-sourced Aggregate for a subscription management domain.
  Maintains independent state and event history for multiple subscription IDs.
  """

  use GenServer

  @type id :: any()
  @type command ::
          {:create, String.t()}
          | {:activate}
          | {:suspend, String.t()}
          | {:cancel}
          | {:reactivate}
  @type event :: %{atom() => any(), type: atom()}
  @type state_map ::
          %{plan: String.t(), status: atom(), reason: String.t() | nil} | nil

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

  defp validate_command(current_state, command) do
    # TODO
  end

  # --- Domain Logic: Event Application ---

  defp apply_event(%{type: :subscription_created, plan: plan}, _nil_state) do
    %{plan: plan, status: :pending, reason: nil}
  end

  defp apply_event(%{type: :subscription_activated}, state) do
    %{state | status: :active}
  end

  defp apply_event(%{type: :subscription_suspended, reason: reason}, state) do
    %{state | status: :suspended, reason: reason}
  end

  defp apply_event(%{type: :subscription_cancelled}, state) do
    %{state | status: :cancelled, reason: nil}
  end

  defp apply_event(%{type: :subscription_reactivated}, state) do
    %{state | status: :active, reason: nil}
  end
end
```