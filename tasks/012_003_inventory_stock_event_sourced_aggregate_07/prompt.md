# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `state` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# Design brief: `InventoryAggregate`

## Problem

Build an Elixir GenServer module called `InventoryAggregate` that maintains its state through event sourcing for a product inventory domain. Each command is first validated against the current state, then zero or more event structs/maps are produced, then those events are applied one by one to the state, and finally they are appended to the event history.

## Constraints

- Deliver the complete module in a single file.
- Use only the OTP standard library — no external dependencies.
- Each aggregate `id` must be tracked independently: commands on `"prod:1"` should have no effect on `"prod:2"`.
- Commands are tuples: `{:register, product_name, sku}`, `{:receive_stock, quantity}`, `{:ship_stock, quantity}`, `{:adjust, quantity}`.
- Events are maps carrying at least a `:type` key. Use the types `:product_registered`, `:stock_received`, `:stock_shipped`, `:stock_adjusted`. Beyond `:type`, each event must carry the data relevant to it:
  - the `:product_registered` event must include the product name (under `:name` or `:product_name`) and the `:sku`;
  - the `:stock_received`, `:stock_shipped`, and `:stock_adjusted` events must each include a `:quantity` key holding the command's quantity — the signed value for adjustments (e.g. `-20` for `{:adjust, -20}`).

## Required interface

1. `InventoryAggregate.start_link(opts)` — starts the process. It should accept a `:name` option for process registration.

2. `InventoryAggregate.execute(server, id, command)` — validates the command against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. If the command succeeds, return `{:ok, events}` where `events` is the list of new events produced by that command. If the command fails validation, return `{:error, reason}`.

3. `InventoryAggregate.state(server, id)` — returns the current state of the aggregate. If the aggregate has never received a command, return `nil`. Otherwise return a map with at least `:name`, `:sku`, `:quantity_on_hand`, and `:status` keys (`:status` is `:registered` after registration).

4. `InventoryAggregate.events(server, id)` — returns the full ordered list of events for that aggregate, oldest first.

## Acceptance criteria

Validation rules that must hold:

- `:register` must fail with `{:error, :already_registered}` if the product is already registered.
- `:receive_stock` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity must be positive or fail with `{:error, :invalid_quantity}`.
- `:ship_stock` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity must be positive or fail with `{:error, :invalid_quantity}`. Must fail with `{:error, :insufficient_stock}` if quantity_on_hand is less than the shipment quantity.
- `:adjust` must fail with `{:error, :not_registered}` if the product hasn't been registered. Quantity can be positive or negative but not zero — fail with `{:error, :invalid_quantity}` if zero. Must fail with `{:error, :insufficient_stock}` if a negative adjustment would bring quantity_on_hand below zero.

## The module with `state` missing

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

  def state(server, id) do
    # TODO
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

Reply with `state` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
