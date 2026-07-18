# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule InventoryAggregateTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = InventoryAggregate.start_link([])
    %{agg: pid}
  end

  # -------------------------------------------------------
  # Registering a product
  # -------------------------------------------------------

  test "register produces a :product_registered event", %{agg: agg} do
    assert {:ok, [event]} =
             InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})

    assert event.type == :product_registered
  end

  test "state after register has correct name, sku, quantity, and status", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})

    state = InventoryAggregate.state(agg, "prod:1")
    assert state.name == "Widget"
    assert state.sku == "WDG-001"
    assert state.quantity_on_hand == 0
    assert state.status == :registered
  end

  test "registering an already-registered product fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})

    assert {:error, :already_registered} =
             InventoryAggregate.execute(agg, "prod:1", {:register, "Other", "OTH-001"})
  end

  # -------------------------------------------------------
  # Receiving stock
  # -------------------------------------------------------

  test "receive_stock increases quantity_on_hand", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})
    assert event.type == :stock_received

    state = InventoryAggregate.state(agg, "prod:1")
    assert state.quantity_on_hand == 100
  end

  test "multiple receives accumulate", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 50})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 75})

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 125
  end

  test "receive_stock on unregistered product fails", %{agg: agg} do
    assert {:error, :not_registered} =
             InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 10})
  end

  test "receive_stock of zero or negative quantity fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})

    assert {:error, :invalid_quantity} =
             InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 0})

    assert {:error, :invalid_quantity} =
             InventoryAggregate.execute(agg, "prod:1", {:receive_stock, -10})
  end

  # -------------------------------------------------------
  # Shipping stock
  # -------------------------------------------------------

  test "ship_stock decreases quantity_on_hand", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 40})
    assert event.type == :stock_shipped

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 60
  end

  test "ship exact quantity succeeds and leaves zero", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 50})
    assert {:ok, _} = InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 50})

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 0
  end

  test "ship more than available stock fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 30})

    assert {:error, :insufficient_stock} =
             InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 31})

    # Quantity unchanged after failed shipment
    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 30
  end

  test "ship_stock on unregistered product fails", %{agg: agg} do
    assert {:error, :not_registered} =
             InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 10})
  end

  test "ship_stock of zero or negative quantity fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})

    assert {:error, :invalid_quantity} =
             InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 0})

    assert {:error, :invalid_quantity} =
             InventoryAggregate.execute(agg, "prod:1", {:ship_stock, -5})
  end

  # -------------------------------------------------------
  # Stock adjustments
  # -------------------------------------------------------

  test "positive adjustment increases quantity", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 50})
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:adjust, 10})
    assert event.type == :stock_adjusted
    assert event.quantity == 10

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 60
  end

  test "negative adjustment decreases quantity", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 50})
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:adjust, -20})
    assert event.quantity == -20

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 30
  end

  test "adjustment that would go below zero fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 10})

    assert {:error, :insufficient_stock} =
             InventoryAggregate.execute(agg, "prod:1", {:adjust, -11})

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 10
  end

  test "zero adjustment fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    assert {:error, :invalid_quantity} = InventoryAggregate.execute(agg, "prod:1", {:adjust, 0})
  end

  test "adjust on unregistered product fails", %{agg: agg} do
    assert {:error, :not_registered} = InventoryAggregate.execute(agg, "prod:1", {:adjust, 5})
  end

  # -------------------------------------------------------
  # Event history
  # -------------------------------------------------------

  test "events returns full ordered history", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})
    InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 30})

    events = InventoryAggregate.events(agg, "prod:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :product_registered,
             :stock_received,
             :stock_shipped
           ]
  end

  test "failed commands produce no events", %{agg: agg} do
    # TODO
  end

  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert InventoryAggregate.events(agg, "nonexistent") == []
  end

  # -------------------------------------------------------
  # State queries
  # -------------------------------------------------------

  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert InventoryAggregate.state(agg, "nonexistent") == nil
  end

  # -------------------------------------------------------
  # Aggregate independence
  # -------------------------------------------------------

  test "different aggregate ids are completely independent", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 200})

    InventoryAggregate.execute(agg, "prod:2", {:register, "Gadget", "GDG-001"})
    InventoryAggregate.execute(agg, "prod:2", {:receive_stock, 10})

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 200
    assert InventoryAggregate.state(agg, "prod:2").quantity_on_hand == 10

    assert length(InventoryAggregate.events(agg, "prod:1")) == 2
    assert length(InventoryAggregate.events(agg, "prod:2")) == 2
  end

  # -------------------------------------------------------
  # Full scenario — replay verification
  # -------------------------------------------------------

  test "full command sequence produces correct state and event history", %{agg: agg} do
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:register, "Bolt", "BLT-100"})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:receive_stock, 500})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:receive_stock, 300})
    {:error, :insufficient_stock} = InventoryAggregate.execute(agg, "a", {:ship_stock, 900})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:ship_stock, 150})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:adjust, -50})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:ship_stock, 600})

    state = InventoryAggregate.state(agg, "a")
    assert state.name == "Bolt"
    assert state.sku == "BLT-100"
    assert state.quantity_on_hand == 0
    assert state.status == :registered

    events = InventoryAggregate.events(agg, "a")
    # 6 successful commands = 6 events
    assert length(events) == 6

    types = Enum.map(events, & &1.type)

    assert types == [
             :product_registered,
             :stock_received,
             :stock_received,
             :stock_shipped,
             :stock_adjusted,
             :stock_shipped
           ]
  end

  # -------------------------------------------------------
  # Event content
  # -------------------------------------------------------

  test "events carry relevant data", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 200})
    InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 75})

    [registered, received, shipped] = InventoryAggregate.events(agg, "prod:1")

    assert registered.type == :product_registered
    assert Map.has_key?(registered, :name) or Map.has_key?(registered, :product_name)
    assert Map.has_key?(registered, :sku)

    assert received.type == :stock_received
    assert received.quantity == 200

    assert shipped.type == :stock_shipped
    assert shipped.quantity == 75
  end

  test "start_link registers the process under the given :name option" do
    name = :inventory_named_process_test
    {:ok, _pid} = InventoryAggregate.start_link(name: name)

    assert {:ok, [event]} =
             InventoryAggregate.execute(name, "prod:1", {:register, "Widget", "WDG-001"})

    assert event.type == :product_registered
    assert InventoryAggregate.state(name, "prod:1").status == :registered
  end

  test "negative adjustment landing on exactly zero succeeds", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 10})

    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:adjust, -10})
    assert event.type == :stock_adjusted
    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 0
  end
end
```
