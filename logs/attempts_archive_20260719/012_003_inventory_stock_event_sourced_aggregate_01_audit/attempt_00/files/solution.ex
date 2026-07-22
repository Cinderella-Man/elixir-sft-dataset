defmodule InventoryAggregate do
  @moduledoc """
  An event-sourced Aggregate for a product inventory domain.
  Maintains independent state and event history for multiple product IDs.
  """

  use GenServer

  @type id :: any()
  @type command ::
          {:register, String.t(), String.t()}
          | {:receive_stock, number()}
          | {:ship_stock, number()}
          | {:adjust, number()}
  @type event :: %{atom() => any(), type: atom()}
  @type state_map ::
          %{name: String.t(), sku: String.t(), quantity_on_hand: number(), status: :registered}
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

  defp validate_command(nil, {:register, name, sku}) do
    {:ok, [%{type: :product_registered, name: name, sku: sku}]}
  end

  defp validate_command(_state, {:register, _name, _sku}), do: {:error, :already_registered}

  defp validate_command(nil, _command), do: {:error, :not_registered}

  defp validate_command(_state, {:receive_stock, quantity}) do
    cond do
      quantity <= 0 -> {:error, :invalid_quantity}
      true -> {:ok, [%{type: :stock_received, quantity: quantity}]}
    end
  end

  defp validate_command(state, {:ship_stock, quantity}) do
    cond do
      quantity <= 0 -> {:error, :invalid_quantity}
      state.quantity_on_hand < quantity -> {:error, :insufficient_stock}
      true -> {:ok, [%{type: :stock_shipped, quantity: quantity}]}
    end
  end

  defp validate_command(state, {:adjust, quantity}) do
    cond do
      quantity == 0 -> {:error, :invalid_quantity}
      state.quantity_on_hand + quantity < 0 -> {:error, :insufficient_stock}
      true -> {:ok, [%{type: :stock_adjusted, quantity: quantity}]}
    end
  end

  # --- Domain Logic: Event Application ---

  defp apply_event(%{type: :product_registered, name: name, sku: sku}, _nil_state) do
    %{name: name, sku: sku, quantity_on_hand: 0, status: :registered}
  end

  defp apply_event(%{type: :stock_received, quantity: quantity}, state) do
    %{state | quantity_on_hand: state.quantity_on_hand + quantity}
  end

  defp apply_event(%{type: :stock_shipped, quantity: quantity}, state) do
    %{state | quantity_on_hand: state.quantity_on_hand - quantity}
  end

  defp apply_event(%{type: :stock_adjusted, quantity: quantity}, state) do
    %{state | quantity_on_hand: state.quantity_on_hand + quantity}
  end
end
