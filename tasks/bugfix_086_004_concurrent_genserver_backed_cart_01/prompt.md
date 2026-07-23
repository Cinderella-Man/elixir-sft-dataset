# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

I need a shopping cart backed by a GenServer and I'd like you to write it for me. Call the module `CartServer`. The idea is one process per cart, so that when a bunch of callers hammer the same cart concurrently, the updates get serialized safely instead of stepping on each other.

Here's the public API I'm after — every client function takes the cart's `pid`:

`CartServer.start_link(opts \\ [])` starts a cart process and hands back `{:ok, pid}`. It should accept a `:tax_rate` option (a float, e.g. `0.08`), and when nobody passes one it defaults to `0.0`.

`CartServer.add_item(pid, product_id, quantity, unit_price)` adds the given quantity of a product at the given unit price. If that product is already in the cart, bump its quantity rather than duplicating the line. It returns `:ok`, or `{:error, :invalid_quantity}` when quantity isn't a positive integer — and in that error case I want the cart left exactly as it was, no partial mutation.

`CartServer.remove_item(pid, product_id)` drops a product entirely and returns `:ok`. If the product isn't there, it's just a no-op (still `:ok`).

`CartServer.update_quantity(pid, product_id, quantity)` sets the quantity of an item that already exists. A quantity of 0 means remove the item and return `:ok`. If the product isn't present at all, return `{:error, :not_found}`. If the quantity is negative, return `{:error, :invalid_quantity}`. Anything else, return `:ok`.

`CartServer.totals(pid)` gives me back a map containing `:subtotal` — the sum over items of `unit_price * quantity` after per-item discounts are applied; `:tax` — that's `subtotal * tax_rate`; `:grand_total` — `subtotal + tax`; and `:items` — a list of maps, one per cart item, each carrying `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`. I want `:discount_rate` expressed as a fraction: `0.1` when the bulk discount kicks in, otherwise `0.0`. For an empty cart, `:items` should come back as `[]` and `:subtotal`, `:tax`, and `:grand_total` should each be `0.0`.

The discount rule itself: any line item with quantity ≥ 10 gets a 10% discount applied to its unit price before the line total is computed. Items under 10 get no discount.

Since every state change funnels through the GenServer, concurrent `add_item` calls against the same product from many processes have to accumulate correctly with zero lost updates — that's really the point of the exercise. All monetary values are floats. Please give me the complete module in a single file, with no external dependencies beyond OTP's `GenServer`.

## The buggy module

```elixir
defmodule CartServer do
  @moduledoc """
  A shopping cart backed by a GenServer — one process per cart.

  All state changes flow through the process mailbox, so concurrent updates
  from many callers are serialized and never lose writes.  The pricing rule
  matches the classic cart: any line item with quantity ≥ 10 receives a 10 %
  unit-price discount before its line total.
  """

  use GenServer

  @bulk_threshold 10
  @bulk_rate 0.10

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc "Starts a cart process. Accepts a `:tax_rate` option (default `0.0`)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, 0.0)
    GenServer.start_link(__MODULE__, tax_rate)
  end

  @doc "Adds `quantity` of `product_id` at `unit_price`, summing existing quantities."
  @spec add_item(pid(), term(), pos_integer(), float()) ::
          :ok | {:error, :invalid_quantity}
  def add_item(pid, product_id, quantity, unit_price),
    do: GenServer.call(pid, {:add_item, product_id, quantity, unit_price})

  @doc "Removes `product_id` entirely; a no-op when absent."
  @spec remove_item(pid(), term()) :: :ok
  def remove_item(pid, product_id),
    do: GenServer.call(pid, {:remove_item, product_id})

  @doc "Sets an existing item's quantity; 0 removes it."
  @spec update_quantity(pid(), term(), non_neg_integer()) ::
          :ok | {:error, :not_found | :invalid_quantity}
  def update_quantity(pid, product_id, quantity),
    do: GenServer.call(pid, {:update_quantity, product_id, quantity})

  @doc "Returns the current totals map for the cart."
  @spec totals(pid()) :: %{
          subtotal: float(),
          tax: float(),
          grand_total: float(),
          items: [map()]
        }
  def totals(pid), do: GenServer.call(pid, :totals)

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(tax_rate) do
    {:error, %{tax_rate: tax_rate, items: %{}}}
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

## Failing test report

```
7 of 7 test(s) failed:

  * test start_link defaults tax rate to zero
      no match of right hand side value:
      
          {:error, %{items: %{}, tax_rate: 0.0}}
      

  * test add_item accumulates and validates quantity
      no match of right hand side value:
      
          {:error, %{items: %{}, tax_rate: 0.0}}
      

  * test remove_item and update_quantity
      no match of right hand side value:
      
          {:error, %{items: %{}, tax_rate: 0.0}}
      

  * test per-item discount at threshold and tax on discounted subtotal
      no match of right hand side value:
      
          {:error, %{items: %{}, tax_rate: 0.1}}
      

  (…3 more)
```
