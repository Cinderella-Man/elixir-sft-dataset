# Task: Implement `handle_call/3` for `CartServer`

Implement the GenServer `handle_call/3` callback (one function, several clauses) that
serves every synchronous client request routed through `GenServer.call/2`. The server
state is a map of the form `%{tax_rate: float(), items: %{}}`, where `items` maps a
`product_id` to an item map `%{product_id: term(), quantity: pos_integer(), unit_price: float()}`.
Provide the following clauses:

- **`{:add_item, product_id, quantity, unit_price}`** — valid only when `quantity` is an
  integer greater than `0` (enforce this with a guard). Insert the product if it is
  absent, or, if it already exists, increase its stored `quantity` by the incoming
  `quantity` (leaving the existing `unit_price` unchanged). Use `Map.update/4` so the
  accumulation is atomic within the process. Reply `:ok` with the updated state.
- **`{:add_item, _, _, _}`** (fallback for a non-positive or non-integer quantity) — reply
  `{:error, :invalid_quantity}` without changing the state.
- **`{:remove_item, product_id}`** — delete the product from `items` (a no-op when it is
  absent) and reply `:ok` with the updated state.
- **`{:update_quantity, product_id, quantity}`** — valid only when `quantity` is an integer
  `>= 0` (guard). Look the product up in `items`:
  - if it is not present, reply `{:error, :not_found}` and leave the state unchanged;
  - if it is present and `quantity == 0`, delete it and reply `:ok`;
  - otherwise set the item's `quantity` to the new value and reply `:ok`, in both cases
    with the updated state.
- **`{:update_quantity, _, _}`** (fallback for a negative or non-integer quantity) — reply
  `{:error, :invalid_quantity}` without changing the state.
- **`:totals`** — reply with `compute_totals(state)` (the private helper already defined)
  and leave the state unchanged.

Every clause must return a standard `{:reply, reply, new_state}` tuple.

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
    {:ok, %{tax_rate: tax_rate, items: %{}}}
  end

  @impl true
  # TODO

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