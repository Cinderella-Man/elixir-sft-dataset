# Fill in the middle: `Cart.apply_coupon/2`

The `Cart` module below is complete except for one function. Implement the public
`apply_coupon/2` function, whose body has been replaced with `# TODO`.

`apply_coupon/2` validates a coupon and, if it passes, records it on the cart so
that `calculate_totals/1` can later apply it. It takes a `%Cart{}` and a `coupon`
map and must, in order:

1. **Validate the coupon's shape.** A well-formed coupon has a `:code`, a `:type`
   that is either `:percentage` or `:fixed`, and a `:value` that is a non-negative
   number. If the coupon is malformed (missing `:code`, unknown `:type`, or a
   non-number/negative `:value`), return `{:error, :invalid_coupon}`. Use the
   existing `validate_coupon/1` helper.
2. **Reject duplicates.** If a coupon with the same `:code` has already been
   applied to the cart, return `{:error, :already_applied}`. Use the existing
   `ensure_not_applied/2` helper.
3. **Enforce the minimum subtotal.** If the current item subtotal (line totals
   after per-item bulk discounts, before coupons) is below the coupon's
   `:min_subtotal` (defaulting to `0.0`), return `{:error, :below_minimum}`. Use
   the existing `ensure_minimum/2` helper.
4. **Record the coupon.** Otherwise, append the coupon to `cart.coupons`
   (preserving application order) and return `{:ok, cart}`. Store a normalized
   coupon via the existing `normalize/1` helper so downstream code can rely on a
   `:min_subtotal` always being present.

Compose the three validation steps with a `with` expression so that the first
failing check short-circuits and its `{:error, reason}` tuple is returned
unchanged.

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
    # TODO
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
    minimum = Map.get(coupon, :min_subtotal, 0.0)
    if item_subtotal(cart) >= minimum, do: :ok, else: {:error, :below_minimum}
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