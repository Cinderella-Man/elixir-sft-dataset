Implement the private `validate_command/2` function. It takes the current aggregate
state (either `nil` if the aggregate has never been registered, or a state map with
`:name`, `:sku`, `:quantity_on_hand`, and `:status` keys) and a command tuple, and it
must return `{:ok, events}` — where `events` is a list of event maps each carrying at
least a `:type` key — when the command is valid, or `{:error, reason}` when it is not.

It must handle these commands and rules:

- `{:register, name, sku}`: valid only when the state is `nil` (never registered).
  On success produce `[%{type: :product_registered, name: name, sku: sku}]`. If the
  aggregate is already registered, fail with `{:error, :already_registered}`.

- Any non-`:register` command against a `nil` (never-registered) state must fail with
  `{:error, :not_registered}`.

- `{:receive_stock, quantity}`: the quantity must be positive, otherwise fail with
  `{:error, :invalid_quantity}`. On success produce
  `[%{type: :stock_received, quantity: quantity}]`.

- `{:ship_stock, quantity}`: the quantity must be positive, otherwise fail with
  `{:error, :invalid_quantity}`. If `quantity_on_hand` is less than the requested
  quantity, fail with `{:error, :insufficient_stock}`. On success produce
  `[%{type: :stock_shipped, quantity: quantity}]`.

- `{:adjust, quantity}`: the quantity may be positive or negative but must not be zero;
  a zero quantity fails with `{:error, :invalid_quantity}`. If applying the adjustment
  would bring `quantity_on_hand` below zero, fail with `{:error, :insufficient_stock}`.
  On success produce `[%{type: :stock_adjusted, quantity: quantity}]`.

```elixir
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

  # TODO

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
```