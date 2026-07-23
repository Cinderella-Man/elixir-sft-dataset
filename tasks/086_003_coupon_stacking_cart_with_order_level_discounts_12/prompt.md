# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `ensure_minimum`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Design brief: `Cart` — order-level coupon stacking over per-item bulk discounts

## Problem

We need an Elixir context module called `Cart` that implements an in-memory shopping cart with **order-level coupon stacking** layered on top of per-item bulk discounts. The existing per-item bulk discount behaviour stays as-is; the new capability is a stack of coupons applied to the order as a whole.

## Constraints

- The `Cart` struct must be a pure data structure — no database, no GenServer, no processes.
- All monetary values are floats.
- Deliver the complete module in a single file with no external dependencies.

## Required interface

The public API must consist of the following functions:

1. `Cart.new(opts \\ [])` — creates a new cart struct. Accepts a `:tax_rate` float (e.g. `0.08`), defaulting to `0.0`.

2. `Cart.add_item(cart, product_id, quantity, unit_price)` — adds the quantity of a product at the unit price, summing quantities for existing products. Reject with `{:error, :invalid_quantity}` if quantity is not a positive integer. Returns `{:ok, cart}`.

3. `Cart.remove_item(cart, product_id)` — removes a product entirely; a no-op if absent. Returns the updated cart struct directly (not wrapped in an `{:ok, _}` tuple).

4. `Cart.update_quantity(cart, product_id, quantity)` — sets an existing item's quantity. 0 removes it; unknown product returns `{:error, :not_found}`; negative returns `{:error, :invalid_quantity}`. Returns `{:ok, cart}`.

5. `Cart.apply_coupon(cart, coupon)` — records a coupon on the cart. A coupon is a map with keys `:code`, `:type` (`:percentage` or `:fixed`), `:value` (a non-negative number), and an optional `:min_subtotal` (defaulting to `0.0`). Validation:
   - If the coupon map is malformed (missing `:code`, unknown `:type`, or a non-number/negative `:value`), return `{:error, :invalid_coupon}`.
   - If a coupon with the same `:code` was already applied, return `{:error, :already_applied}`.
   - If the current item subtotal (after per-item discounts) is below the coupon's `:min_subtotal`, return `{:error, :below_minimum}`.
   - Otherwise return `{:ok, cart}` with the coupon appended (application order is preserved).

6. `Cart.calculate_totals(cart)` — returns a map with:
   - `:subtotal` — sum of item line totals after per-item bulk discounts (before coupons)
   - `:discount` — total amount removed by all coupons
   - `:discounted_subtotal` — `subtotal - discount`
   - `:tax` — `discounted_subtotal * tax_rate`
   - `:grand_total` — `discounted_subtotal + tax`
   - `:coupons` — the list of applied coupon codes, in application order
   - `:items` — a list of maps, one per item, each with `:product_id`, `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`

## Acceptance criteria

- **Per-item discount rule** (unchanged from the base cart): a line item with quantity ≥ 10 gets a 10% discount on its unit price before its line total.
- **Coupon stacking rule**: coupons apply **sequentially in application order** against a running amount that starts at the item subtotal. A `:percentage` coupon removes `running * value`; a `:fixed` coupon removes `min(value, running)` (a fixed coupon can never push the running amount below zero). Because order matters, applying a percentage then a fixed coupon can differ from the reverse.
- All six functions above behave exactly as specified, including every error tuple and return-shape distinction.

## The module with `ensure_minimum` missing

```elixir
defmodule Cart do
  @moduledoc """
  An in-memory shopping cart with per-item bulk discounts and order-level
  coupon stacking.

  Coupons are validated and recorded via `apply_coupon/2` and then applied,
  in order, at `calculate_totals/1` time.  A percentage coupon removes a
  fraction of the running amount; a fixed coupon removes a capped absolute
  amount that can never drive the running amount below zero.
  """

  @bulk_threshold 10
  @bulk_rate 0.10

  defmodule Item do
    @moduledoc "A single line item inside a `Cart`."
    @enforce_keys [:product_id, :quantity, :unit_price]
    defstruct [:product_id, :quantity, :unit_price]
  end

  @enforce_keys [:tax_rate, :items, :coupons]
  defstruct tax_rate: 0.0, items: %{}, coupons: []

  @doc "Creates a new, empty cart with an optional `:tax_rate`."
  @spec new(keyword()) :: %Cart{}
  def new(opts \\ []) do
    %Cart{tax_rate: Keyword.get(opts, :tax_rate, 0.0), items: %{}, coupons: []}
  end

  @doc "Adds `quantity` of `product_id`, summing existing quantities."
  @spec add_item(%Cart{}, term(), pos_integer(), float()) ::
          {:ok, %Cart{}} | {:error, :invalid_quantity}
  def add_item(%Cart{} = cart, product_id, quantity, unit_price)
      when is_integer(quantity) and quantity > 0 do
    updated =
      Map.update(
        cart.items,
        product_id,
        %Item{product_id: product_id, quantity: quantity, unit_price: unit_price},
        fn %Item{} = existing -> %Item{existing | quantity: existing.quantity + quantity} end
      )

    {:ok, %Cart{cart | items: updated}}
  end

  def add_item(%Cart{}, _product_id, _quantity, _unit_price),
    do: {:error, :invalid_quantity}

  @doc "Removes `product_id` entirely; a no-op when absent."
  @spec remove_item(%Cart{}, term()) :: %Cart{}
  def remove_item(%Cart{} = cart, product_id),
    do: %Cart{cart | items: Map.delete(cart.items, product_id)}

  @doc "Sets an existing item's quantity; 0 removes it."
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
        items = Map.put(cart.items, product_id, %Item{item | quantity: quantity})
        {:ok, %Cart{cart | items: items}}
    end
  end

  def update_quantity(%Cart{}, _product_id, _quantity),
    do: {:error, :invalid_quantity}

  @doc """
  Validates and records `coupon` on the cart.

  Returns `{:ok, cart}` or one of `{:error, :invalid_coupon}`,
  `{:error, :already_applied}`, `{:error, :below_minimum}`.
  """
  @spec apply_coupon(%Cart{}, map()) ::
          {:ok, %Cart{}}
          | {:error, :invalid_coupon | :already_applied | :below_minimum}
  def apply_coupon(%Cart{} = cart, coupon) do
    with :ok <- validate_coupon(coupon),
         :ok <- ensure_not_applied(cart, coupon),
         :ok <- ensure_minimum(cart, coupon) do
      {:ok, %Cart{cart | coupons: cart.coupons ++ [normalize(coupon)]}}
    end
  end

  @doc "Computes the totals map, applying all recorded coupons in order."
  @spec calculate_totals(%Cart{}) :: %{
          subtotal: float(),
          discount: float(),
          discounted_subtotal: float(),
          tax: float(),
          grand_total: float(),
          coupons: [term()],
          items: [map()]
        }
  def calculate_totals(%Cart{} = cart) do
    items = cart.items |> Map.values() |> Enum.map(&build_summary/1)
    subtotal = Enum.reduce(items, 0.0, fn i, acc -> acc + i.line_total end)

    {discounted, discount} =
      Enum.reduce(cart.coupons, {subtotal, 0.0}, fn coupon, {running, disc} ->
        amount = coupon_amount(coupon, running)
        {running - amount, disc + amount}
      end)

    tax = discounted * cart.tax_rate

    %{
      items: items,
      subtotal: subtotal,
      discount: discount,
      discounted_subtotal: discounted,
      tax: tax,
      grand_total: discounted + tax,
      coupons: Enum.map(cart.coupons, & &1.code)
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_summary(%Item{} = item) do
    rate = if item.quantity >= @bulk_threshold, do: @bulk_rate, else: 0.0

    %{
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      discount_rate: rate,
      line_total: item.unit_price * (1.0 - rate) * item.quantity
    }
  end

  defp item_subtotal(%Cart{items: items}) do
    items
    |> Map.values()
    |> Enum.reduce(0.0, fn item, acc -> acc + build_summary(item).line_total end)
  end

  defp coupon_amount(%{type: :percentage, value: value}, running), do: running * value
  defp coupon_amount(%{type: :fixed, value: value}, running), do: min(value, running)

  defp validate_coupon(%{code: _code, type: type, value: value})
       when type in [:percentage, :fixed] and is_number(value) and value >= 0,
       do: :ok

  defp validate_coupon(_coupon), do: {:error, :invalid_coupon}

  defp ensure_not_applied(%Cart{coupons: coupons}, %{code: code}) do
    if Enum.any?(coupons, &(&1.code == code)),
      do: {:error, :already_applied},
      else: :ok
  end

  defp ensure_minimum(%Cart{} = cart, coupon) do
    # TODO
  end

  defp normalize(coupon) do
    %{
      code: coupon.code,
      type: coupon.type,
      value: coupon.value,
      min_subtotal: Map.get(coupon, :min_subtotal, 0.0)
    }
  end
end
```

Output only `ensure_minimum` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
