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
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
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
    assert {:error, :already_registered} = InventoryAggregate.execute(agg, "prod:1", {:register, "Other", "OTH-001"})
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
    assert {:error, :not_registered} = InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 10})
  end

  test "receive_stock of zero or negative quantity fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    assert {:error, :invalid_quantity} = InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 0})
    assert {:error, :invalid_quantity} = InventoryAggregate.execute(agg, "prod:1", {:receive_stock, -10})
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
    assert {:error, :not_registered} = InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 10})
  end

  test "ship_stock of zero or negative quantity fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})
    assert {:error, :invalid_quantity} = InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 0})
    assert {:error, :invalid_quantity} = InventoryAggregate.execute(agg, "prod:1", {:ship_stock, -5})
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

    assert {:error, :insufficient_stock} = InventoryAggregate.execute(agg, "prod:1", {:adjust, -11})
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
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 999})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, -5})

    events = InventoryAggregate.events(agg, "prod:1")
    assert length(events) == 1
    assert hd(events).type == :product_registered
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
end
