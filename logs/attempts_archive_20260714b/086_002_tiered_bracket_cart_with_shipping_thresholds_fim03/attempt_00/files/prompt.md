# Fill in the private `shipping_cost/3` helper

The `Cart` module below is complete **except** for the body of the private
helper `shipping_cost/3`, which has been replaced with `# TODO`.

Implement the private `shipping_cost/3` function used by `calculate_totals/1`.
It computes the shipping charge for an order. It receives the list of built item
summaries, the discounted `subtotal`, and the `%Cart{}` struct.

Behaviour:

- If the item list is **empty**, shipping is `0.0` — the cart has nothing in it,
  so nothing ships.
- Otherwise, read `:free_shipping_threshold` and `:shipping_flat` from the cart.
  If `:free_shipping_threshold` is a number and the discounted `subtotal` is
  greater than or equal to that threshold, shipping is waived and the cost is
  `0.0`. In every other case (threshold is `nil` or not met), shipping is the
  cart's `:shipping_flat` value.

Implement it as two clauses (the empty-list clause and the general clause) so the
empty-cart case is handled by pattern matching. Do not change any other function.

```elixir
defmodule Cart do
  @moduledoc """
  An in-memory shopping cart with tiered bulk-discount brackets and
  shipping-threshold logic.

  Each line item receives the highest applicable quantity-bracket discount.
  Shipping is a flat cost that may be waived once the discounted subtotal
  reaches a configured threshold.  Tax is charged on the discounted subtotal
  only — never on shipping.
  """

  @default_tiers [{10, 0.05}, {25, 0.10}, {50, 0.15}]

  defmodule Item do
    @moduledoc "A single line item inside a `Cart`."
    @enforce_keys [:product_id, :quantity, :unit_price]
    defstruct [:product_id, :quantity, :unit_price]
  end

  @enforce_keys [:tax_rate, :items, :discount_tiers, :shipping_flat, :free_shipping_threshold]
  defstruct tax_rate: 0.0,
            items: %{},
            discount_tiers: @default_tiers,
            shipping_flat: 0.0,
            free_shipping_threshold: nil

  @doc "Creates a new, empty cart. See the module doc for supported options."
  @spec new(keyword()) :: %Cart{}
  def new(opts \\ []) do
    %Cart{
      tax_rate: Keyword.get(opts, :tax_rate, 0.0),
      items: %{},
      discount_tiers: Keyword.get(opts, :discount_tiers, @default_tiers),
      shipping_flat: Keyword.get(opts, :shipping_flat, 0.0),
      free_shipping_threshold: Keyword.get(opts, :free_shipping_threshold, nil)
    }
  end

  @doc "Adds `quantity` of `product_id` at `unit_price`, summing existing quantities."
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
        updated = Map.put(cart.items, product_id, %Item{item | quantity: quantity})
        {:ok, %Cart{cart | items: updated}}
    end
  end

  def update_quantity(%Cart{}, _product_id, _quantity),
    do: {:error, :invalid_quantity}

  @doc "Computes the totals map for the cart's current state."
  @spec calculate_totals(%Cart{}) :: %{
          subtotal: float(),
          tax: float(),
          shipping: float(),
          grand_total: float(),
          items: [map()]
        }
  def calculate_totals(%Cart{} = cart) do
    items =
      cart.items
      |> Map.values()
      |> Enum.map(&build_summary(&1, cart.discount_tiers))

    subtotal = Enum.reduce(items, 0.0, fn i, acc -> acc + i.line_total end)
    tax = subtotal * cart.tax_rate
    shipping = shipping_cost(items, subtotal, cart)

    %{
      items: items,
      subtotal: subtotal,
      tax: tax,
      shipping: shipping,
      grand_total: subtotal + tax + shipping
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_summary(%Item{} = item, tiers) do
    rate = discount_for(item.quantity, tiers)

    %{
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      discount_rate: rate,
      line_total: item.unit_price * (1.0 - rate) * item.quantity
    }
  end

  defp discount_for(quantity, tiers) do
    tiers
    |> Enum.filter(fn {min, _rate} -> quantity >= min end)
    |> case do
      [] -> 0.0
      applicable -> applicable |> Enum.max_by(fn {min, _rate} -> min end) |> elem(1)
    end
  end

  defp shipping_cost(items, subtotal, cart) do
    # TODO
  end
end
```