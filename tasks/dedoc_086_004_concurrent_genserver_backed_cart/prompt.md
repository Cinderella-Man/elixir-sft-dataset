# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule CartServer do
  use GenServer

  @bulk_threshold 10
  @bulk_rate 0.10

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, 0.0)
    GenServer.start_link(__MODULE__, tax_rate)
  end

  def add_item(pid, product_id, quantity, unit_price),
    do: GenServer.call(pid, {:add_item, product_id, quantity, unit_price})

  def remove_item(pid, product_id),
    do: GenServer.call(pid, {:remove_item, product_id})

  def update_quantity(pid, product_id, quantity),
    do: GenServer.call(pid, {:update_quantity, product_id, quantity})

  def totals(pid), do: GenServer.call(pid, :totals)

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(tax_rate) do
    {:ok, %{tax_rate: tax_rate, items: %{}}}
  end

  @impl true
  def handle_call({:add_item, product_id, quantity, unit_price}, _from, state)
      when is_integer(quantity) and quantity > 0 do
    items =
      Map.update(
        state.items,
        product_id,
        %{product_id: product_id, quantity: quantity, unit_price: unit_price},
        fn existing -> %{existing | quantity: existing.quantity + quantity} end
      )

    {:reply, :ok, %{state | items: items}}
  end

  def handle_call({:add_item, _product_id, _quantity, _unit_price}, _from, state),
    do: {:reply, {:error, :invalid_quantity}, state}

  def handle_call({:remove_item, product_id}, _from, state),
    do: {:reply, :ok, %{state | items: Map.delete(state.items, product_id)}}

  def handle_call({:update_quantity, product_id, quantity}, _from, state)
      when is_integer(quantity) and quantity >= 0 do
    case Map.fetch(state.items, product_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, _item} when quantity == 0 ->
        {:reply, :ok, %{state | items: Map.delete(state.items, product_id)}}

      {:ok, item} ->
        updated = Map.put(state.items, product_id, %{item | quantity: quantity})
        {:reply, :ok, %{state | items: updated}}
    end
  end

  def handle_call({:update_quantity, _product_id, _quantity}, _from, state),
    do: {:reply, {:error, :invalid_quantity}, state}

  def handle_call(:totals, _from, state),
    do: {:reply, compute_totals(state), state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp compute_totals(state) do
    items =
      state.items
      |> Map.values()
      |> Enum.map(&build_summary/1)

    subtotal = Enum.reduce(items, 0.0, fn i, acc -> acc + i.line_total end)
    tax = subtotal * state.tax_rate

    %{
      items: items,
      subtotal: subtotal,
      tax: tax,
      grand_total: subtotal + tax
    }
  end

  defp build_summary(item) do
    rate = if item.quantity >= @bulk_threshold, do: @bulk_rate, else: 0.0

    %{
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      discount_rate: rate,
      line_total: item.unit_price * (1.0 - rate) * item.quantity
    }
  end
end
```
