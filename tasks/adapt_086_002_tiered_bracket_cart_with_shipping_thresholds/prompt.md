# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Cart do
  @moduledoc """
  An in-memory shopping cart context.

  Manages a collection of line items and computes subtotals, tax, and grand
  totals entirely in-process — no database or GenServer required.

  ## Discount rule
  Any line item whose quantity is ≥ 10 receives a 10 % discount on its unit
  price before the line total is calculated.  Items below that threshold are
  priced at full rate.

  ## Example

      iex> cart = Cart.new(tax_rate: 0.08)
      iex> cart = Cart.add_item(cart, "sku-1", 2, 9.99) |> elem(1)
      iex> cart = Cart.add_item(cart, "sku-2", 10, 5.00) |> elem(1)
      iex> Cart.calculate_totals(cart)
      %{
        subtotal: 64.98,       # (2 * 9.99) + (10 * 5.00 * 0.90)
        tax: 5.1984,
        grand_total: 70.1784,
        items: [...]
      }
  """

  @bulk_discount_threshold 10
  @bulk_discount_rate 0.10

  # ---------------------------------------------------------------------------
  # Structs
  # ---------------------------------------------------------------------------

  defmodule Item do
    @moduledoc "A single line item inside a `Cart`."

    @enforce_keys [:product_id, :quantity, :unit_price]
    defstruct [:product_id, :quantity, :unit_price, discount_rate: 0.0]
  end

  @enforce_keys [:tax_rate, :items]
  defstruct tax_rate: 0.0, items: %{}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates and returns a new, empty `%Cart{}`.

  ## Options

    * `:tax_rate` — a non-negative float representing the sales-tax rate,
      e.g. `0.08` for 8 %.  Defaults to `0.0`.

  ## Examples

      iex> Cart.new()
      %Cart{tax_rate: 0.0, items: %{}}

      iex> Cart.new(tax_rate: 0.07)
      %Cart{tax_rate: 0.07, items: %{}}
  """
  @spec new(keyword()) :: %Cart{}
  def new(opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, 0.0)
    %Cart{tax_rate: tax_rate, items: %{}}
  end

  @doc """
  Adds `quantity` units of `product_id` at `unit_price` to `cart`.

  If the product already exists the quantities are summed; the stored
  `unit_price` is left unchanged (first price wins).

  Returns `{:ok, updated_cart}` on success or `{:error, :invalid_quantity}`
  when `quantity` is not a positive integer.

  ## Examples

      iex> {:ok, cart} = Cart.new() |> Cart.add_item("p1", 3, 4.99)
      iex> cart.items["p1"].quantity
      3

      iex> Cart.new() |> Cart.add_item("p1", 0, 4.99)
      {:error, :invalid_quantity}
  """
  @spec add_item(%Cart{}, term(), pos_integer(), float()) ::
          {:ok, %Cart{}} | {:error, :invalid_quantity}
  def add_item(%Cart{} = cart, product_id, quantity, unit_price)
      when is_integer(quantity) and quantity > 0 do
    updated_items =
      Map.update(
        cart.items,
        product_id,
        %Item{product_id: product_id, quantity: quantity, unit_price: unit_price},
        fn %Item{} = existing -> %Item{existing | quantity: existing.quantity + quantity} end
      )

    {:ok, %Cart{cart | items: updated_items}}
  end

  def add_item(%Cart{}, _product_id, _quantity, _unit_price),
    do: {:error, :invalid_quantity}

  @doc """
  Removes `product_id` from `cart` entirely.

  If the product is not present the cart is returned unchanged (no error).

  ## Examples

      iex> {:ok, cart} = Cart.new() |> Cart.add_item("p1", 1, 1.00)
      iex> cart = Cart.remove_item(cart, "p1")
      iex> Map.has_key?(cart.items, "p1")
      false

      iex> cart = Cart.new()
      iex> Cart.remove_item(cart, "missing") == cart
      true
  """
  @spec remove_item(%Cart{}, term()) :: %Cart{}
  def remove_item(%Cart{} = cart, product_id) do
    %Cart{cart | items: Map.delete(cart.items, product_id)}
  end

  @doc """
  Sets the quantity of an existing `product_id` to `quantity`.

  * If `quantity` is `0` the item is removed entirely.
  * If the product is not in the cart, returns `{:error, :not_found}`.
  * If `quantity` is negative, returns `{:error, :invalid_quantity}`.

  ## Examples

      iex> {:ok, cart} = Cart.new() |> Cart.add_item("p1", 3, 2.50)
      iex> {:ok, cart} = Cart.update_quantity(cart, "p1", 7)
      iex> cart.items["p1"].quantity
      7

      iex> {:ok, cart} = Cart.new() |> Cart.add_item("p1", 3, 2.50)
      iex> cart = Cart.update_quantity(cart, "p1", 0) |> elem(1)
      iex> Map.has_key?(cart.items, "p1")
      false
  """
  @spec update_quantity(%Cart{}, term(), non_neg_integer()) ::
          {:ok, %Cart{}} | {:error, :not_found | :invalid_quantity}
  def update_quantity(%Cart{} = cart, product_id, quantity)
      when is_integer(quantity) and quantity >= 0 do
    case Map.fetch(cart.items, product_id) do
      :error ->
        {:error, :not_found}

      {:ok, _item} when quantity == 0 ->
        {:ok, remove_item(cart, product_id)}

      {:ok, %Item{} = item} ->
        updated_item = %Item{item | quantity: quantity}
        {:ok, %Cart{cart | items: Map.put(cart.items, product_id, updated_item)}}
    end
  end

  def update_quantity(%Cart{}, _product_id, _quantity),
    do: {:error, :invalid_quantity}

  @doc """
  Calculates and returns a summary map for the current state of `cart`.

  The returned map contains:

    * `:items`       — list of per-item breakdown maps (see below)
    * `:subtotal`    — sum of all `:line_total` values
    * `:tax`         — `subtotal * tax_rate`
    * `:grand_total` — `subtotal + tax`

  Each entry in `:items` is a map with:

    * `:product_id`    — the product identifier
    * `:quantity`      — current quantity
    * `:unit_price`    — original unit price (before any discount)
    * `:discount_rate` — `0.10` when quantity ≥ 10, otherwise `0.0`
    * `:line_total`    — `unit_price * (1 - discount_rate) * quantity`

  ## Examples

      iex> cart = Cart.new(tax_rate: 0.10)
      iex> {:ok, cart} = Cart.add_item(cart, "a", 10, 20.00)
      iex> totals = Cart.calculate_totals(cart)
      iex> totals.subtotal
      180.0    # 10 * 20.00 * 0.90
      iex> totals.tax
      18.0
      iex> totals.grand_total
      198.0
  """
  @spec calculate_totals(%Cart{}) :: %{
          subtotal: float(),
          tax: float(),
          grand_total: float(),
          items: [map()]
        }
  def calculate_totals(%Cart{items: items, tax_rate: tax_rate}) do
    item_summaries =
      items
      |> Map.values()
      |> Enum.map(&build_item_summary/1)

    subtotal = Enum.reduce(item_summaries, 0.0, fn i, acc -> acc + i.line_total end)
    tax = subtotal * tax_rate
    grand_total = subtotal + tax

    %{
      items: item_summaries,
      subtotal: subtotal,
      tax: tax,
      grand_total: grand_total
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_item_summary(%Item{
         product_id: product_id,
         quantity: quantity,
         unit_price: unit_price
       }) do
    discount_rate = if quantity >= @bulk_discount_threshold, do: @bulk_discount_rate, else: 0.0
    line_total = unit_price * (1.0 - discount_rate) * quantity

    %{
      product_id: product_id,
      quantity: quantity,
      unit_price: unit_price,
      discount_rate: discount_rate,
      line_total: line_total
    }
  end
end
```

## New specification

Write me an Elixir context module called `Cart` that implements an in-memory shopping cart with **tiered bulk-discount brackets** and **shipping-threshold** logic.

I need these functions in the public API:
- `Cart.new(opts \\ [])` to create a new cart struct. It should accept:
  - `:tax_rate` — a float (e.g. `0.08` for 8%). Defaults to `0.0`.
  - `:discount_tiers` — a list of `{min_quantity, rate}` tuples describing per-line quantity brackets. Defaults to `[{10, 0.05}, {25, 0.10}, {50, 0.15}]`.
  - `:shipping_flat` — a flat shipping cost (float) added to the order. Defaults to `0.0`.
  - `:free_shipping_threshold` — if the discounted subtotal is greater than or equal to this value, shipping is waived. Defaults to `nil` (never waived automatically).
- `Cart.add_item(cart, product_id, quantity, unit_price)` which adds the given quantity of a product at the given unit price. If the product already exists, increase its quantity. Reject with `{:error, :invalid_quantity}` if quantity is not a positive integer. Returns `{:ok, cart}` on success.
- `Cart.remove_item(cart, product_id)` which removes a product entirely. If the product is not present, return the cart unchanged.
- `Cart.update_quantity(cart, product_id, quantity)` which sets the quantity of an existing item. If quantity is 0, remove the item. If the product is not in the cart, return `{:error, :not_found}`. Reject with `{:error, :invalid_quantity}` if quantity is negative. Returns `{:ok, cart}` on success.
- `Cart.calculate_totals(cart)` which returns a map with:
  - `:subtotal` — sum of each item's line total after its bracket discount
  - `:tax` — `subtotal * tax_rate` (tax is charged on the discounted subtotal only, NOT on shipping)
  - `:shipping` — the shipping cost for this order (see rules below)
  - `:grand_total` — `subtotal + tax + shipping`
  - `:items` — a list of maps, one per cart item, each with `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`

Bracket discount rule: for each line item, choose the **highest applicable tier** — the tier with the largest `min_quantity` that is less than or equal to the line's quantity. Apply that tier's rate to the unit price before computing the line total. If no tier applies, the discount rate is `0.0`.

Shipping rule: if the cart has **no items**, shipping is `0.0`. Otherwise, if `:free_shipping_threshold` is a number and the discounted subtotal is greater than or equal to it, shipping is `0.0`; otherwise shipping is `:shipping_flat`.

The `Cart` struct must be a pure data structure — no database, no GenServer, no processes. All monetary values are floats. Give me the complete module in a single file with no external dependencies.

## Additional interface contract

- The cart returned by `Cart.new/1` is a struct whose configuration is exposed as public fields matching the options above — `:tax_rate`, `:discount_tiers`, `:shipping_flat`, and `:free_shipping_threshold` hold the configured (or default) values — plus an `:items` field, a map keyed by product id that is `%{}` for a new, empty cart.
