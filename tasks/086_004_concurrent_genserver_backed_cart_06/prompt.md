# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `totals` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Write me an Elixir module called `CartServer` that implements a shopping cart as a **GenServer** — one process per cart — so that concurrent updates from many callers are serialized safely.

I need this public API (all client functions take the cart's `pid`):
- `CartServer.start_link(opts \\ [])` — starts a cart process and returns `{:ok, pid}`. Accepts a `:tax_rate` option (a float, e.g. `0.08`), defaulting to `0.0`.
- `CartServer.add_item(pid, product_id, quantity, unit_price)` — adds the quantity of a product at the unit price. If the product already exists, increase its quantity. Returns `:ok`, or `{:error, :invalid_quantity}` if quantity is not a positive integer. When it returns `{:error, :invalid_quantity}` the cart is left unchanged.
- `CartServer.remove_item(pid, product_id)` — removes a product entirely and returns `:ok` (a no-op if absent).
- `CartServer.update_quantity(pid, product_id, quantity)` — sets the quantity of an existing item. If quantity is 0, remove the item and return `:ok`. If the product is not present, return `{:error, :not_found}`. If quantity is negative, return `{:error, :invalid_quantity}`. Otherwise return `:ok`.
- `CartServer.totals(pid)` — returns a map with:
  - `:subtotal` — sum of each item's `unit_price * quantity` after per-item discounts
  - `:tax` — `subtotal * tax_rate`
  - `:grand_total` — `subtotal + tax`
  - `:items` — a list of maps, one per cart item, each with `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`. `:discount_rate` is the discount expressed as a fraction — `0.1` when the bulk discount applies, otherwise `0.0`. An empty cart yields `:items` `[]` and `0.0` for `:subtotal`, `:tax`, and `:grand_total`.

Discount rule: a line item with quantity ≥ 10 gets a 10% discount on its unit price before its line total. Items below 10 receive no discount.

Because all state changes flow through the GenServer, concurrent `add_item` calls to the same product from many processes must accumulate correctly with no lost updates. All monetary values are floats. Give me the complete module in a single file with no external dependencies beyond OTP's `GenServer`.

## The module with `totals` missing

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
  def totals(pid) do
    # TODO
  end

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

Reply with `totals` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
