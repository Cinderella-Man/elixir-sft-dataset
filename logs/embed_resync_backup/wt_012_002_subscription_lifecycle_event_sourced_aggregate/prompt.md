# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir GenServer module called `SubscriptionAggregate` that maintains state through event sourcing for a subscription management domain.

I need these functions in the public API:

- `SubscriptionAggregate.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `SubscriptionAggregate.execute(server, id, command)` which validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. Commands are tuples: `{:create, plan_name}`, `{:activate}`, `{:suspend, reason}`, `{:cancel}`, `{:reactivate}`. If the command succeeds, return `{:ok, events}` where `events` is the list of new events produced by that command. If the command fails validation, return `{:error, reason}` and produce no events.

- `SubscriptionAggregate.state(server, id)` which returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:plan`, `:status`, and `:reason` keys (`:status` starts as `:pending` after creation, and `:reason` starts as `nil`).

- `SubscriptionAggregate.events(server, id)` which returns the full ordered list of events for that aggregate, oldest first. If the aggregate has never received a successful command, return an empty list `[]`.

The event sourcing logic should work as follows: each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, then they are appended to the event history. Events should be maps with at least a `:type` key. Use types like `:subscription_created`, `:subscription_activated`, `:subscription_suspended`, `:subscription_cancelled`, `:subscription_reactivated`. The `:subscription_created` event must also carry a `:plan` key holding the plan name, and the `:subscription_suspended` event must also carry a `:reason` key holding the suspend reason.

Applying events updates the state as follows:
- `:subscription_created` → `:plan` set to the plan name, `:status` set to `:pending`, `:reason` set to `nil`.
- `:subscription_activated` → `:status` set to `:active`.
- `:subscription_suspended` → `:status` set to `:suspended`, `:reason` set to the given reason.
- `:subscription_cancelled` → `:status` set to `:cancelled`, `:reason` reset to `nil`.
- `:subscription_reactivated` → `:status` set to `:active`, `:reason` reset to `nil`.

Validation rules:
- `:create` must fail with `{:error, :already_exists}` if the subscription already exists (state is not nil).
- `:activate` must fail with `{:error, :not_found}` if the subscription hasn't been created. Must fail with `{:error, :not_pending}` if the status is not `:pending`.
- `:suspend` must fail with `{:error, :not_found}` if the subscription hasn't been created. Must fail with `{:error, :not_active}` if the status is not `:active`.
- `:cancel` must fail with `{:error, :not_found}` if the subscription hasn't been created. Must fail with `{:error, :already_cancelled}` if the status is already `:cancelled`. Cancelling succeeds from any other existing status (including `:pending`, `:active`, and `:suspended`).
- `:reactivate` must fail with `{:error, :not_found}` if the subscription hasn't been created. Must fail with `{:error, :not_cancelled}` if the status is not `:cancelled`.

Each aggregate `id` must be tracked independently — commands on `"sub:1"` should have no effect on `"sub:2"`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Module under test

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

  # Create
  defp validate_command(nil, {:create, plan_name}) do
    {:ok, [%{type: :subscription_created, plan: plan_name}]}
  end

  defp validate_command(_state, {:create, _plan_name}), do: {:error, :already_exists}

  # Not Found Catch-all
  defp validate_command(nil, _command), do: {:error, :not_found}

  # Activate
  defp validate_command(%{status: :pending}, {:activate}) do
    {:ok, [%{type: :subscription_activated}]}
  end

  defp validate_command(_state, {:activate}), do: {:error, :not_pending}

  # Suspend
  defp validate_command(%{status: :active}, {:suspend, reason}) do
    {:ok, [%{type: :subscription_suspended, reason: reason}]}
  end

  defp validate_command(_state, {:suspend, _reason}), do: {:error, :not_active}

  # Cancel
  # Must fail only if already cancelled; any other existing status may cancel.
  defp validate_command(%{status: :cancelled}, {:cancel}), do: {:error, :already_cancelled}

  defp validate_command(_state, {:cancel}) do
    {:ok, [%{type: :subscription_cancelled}]}
  end

  # Reactivate
  defp validate_command(%{status: :cancelled}, {:reactivate}) do
    {:ok, [%{type: :subscription_reactivated}]}
  end

  defp validate_command(_state, {:reactivate}), do: {:error, :not_cancelled}

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
