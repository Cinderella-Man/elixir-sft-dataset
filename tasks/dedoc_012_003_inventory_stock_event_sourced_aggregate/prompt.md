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
defmodule InventoryAggregate do
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
