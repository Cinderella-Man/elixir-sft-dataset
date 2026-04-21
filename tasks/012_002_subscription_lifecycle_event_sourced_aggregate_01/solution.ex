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
  # Must fail if already cancelled
  defp validate_command(%{status: :cancelled}, {:cancel}), do: {:error, :already_cancelled}
  # Must fail if not yet active (pending)
  defp validate_command(%{status: :pending}, {:cancel}), do: {:error, :not_active}
  # Success for :active or :suspended
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
