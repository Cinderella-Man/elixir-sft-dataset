# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule SubscriptionAggregate do
  use GenServer

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def execute(server, id, command) do
    GenServer.call(server, {:execute, id, command})
  end

  def state(server, id) do
    GenServer.call(server, {:get_state, id})
  end

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
