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
defmodule Cart do
  @default_tiers [{10, 0.05}, {25, 0.10}, {50, 0.15}]

  defmodule Item do
    @enforce_keys [:product_id, :quantity, :unit_price]
    defstruct [:product_id, :quantity, :unit_price]
  end

  @enforce_keys [:tax_rate, :items, :discount_tiers, :shipping_flat, :free_shipping_threshold]
  defstruct tax_rate: 0.0,
            items: %{},
            discount_tiers: @default_tiers,
            shipping_flat: 0.0,
            free_shipping_threshold: nil

  def new(opts \\ []) do
    %Cart{
      tax_rate: Keyword.get(opts, :tax_rate, 0.0),
      items: %{},
      discount_tiers: Keyword.get(opts, :discount_tiers, @default_tiers),
      shipping_flat: Keyword.get(opts, :shipping_flat, 0.0),
      free_shipping_threshold: Keyword.get(opts, :free_shipping_threshold, nil)
    }
  end

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

  def remove_item(%Cart{} = cart, product_id),
    do: %Cart{cart | items: Map.delete(cart.items, product_id)}

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

  defp shipping_cost([], _subtotal, _cart), do: 0.0

  defp shipping_cost(_items, subtotal, %Cart{
         free_shipping_threshold: threshold,
         shipping_flat: flat
       }) do
    if is_number(threshold) and subtotal >= threshold, do: 0.0, else: flat
  end
end
```
