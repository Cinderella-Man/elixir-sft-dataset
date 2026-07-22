defmodule Cart do
  @moduledoc """
  An in-memory shopping cart with tiered bulk-discount brackets and
  shipping-threshold logic.

  A `Cart` is a pure data structure — there is no database, GenServer, or
  process involved. All operations take a cart and return either a new cart
  or a computed totals map. Every monetary value is a float.

  ## Configuration

  A cart is created with `new/1`, which accepts:

    * `:tax_rate` — a float such as `0.08` for 8%. Defaults to `0.0`.
    * `:discount_tiers` — a list of `{min_quantity, rate}` tuples describing
      per-line quantity brackets. Defaults to
      `[{10, 0.05}, {25, 0.10}, {50, 0.15}]`.
    * `:shipping_flat` — a flat shipping cost added to the order. Defaults to
      `0.0`.
    * `:free_shipping_threshold` — if the discounted subtotal is greater than
      or equal to this value, shipping is waived. Defaults to `nil`.

  ## Discounts

  For each line item the cart chooses the *highest applicable tier* — the tier
  with the largest `min_quantity` that is less than or equal to the line's
  quantity — and applies that tier's rate to the unit price before computing
  the line total. If no tier applies, the discount rate is `0.0`.
  """

  @type product_id :: term()
  @type tier :: {pos_integer(), float()}

  @type item :: %{
          product_id: product_id(),
          quantity: pos_integer(),
          unit_price: float()
        }

  @type t :: %__MODULE__{
          tax_rate: float(),
          discount_tiers: [tier()],
          shipping_flat: float(),
          free_shipping_threshold: number() | nil,
          items: %{optional(product_id()) => item()}
        }

  defstruct tax_rate: 0.0,
            discount_tiers: [{10, 0.05}, {25, 0.10}, {50, 0.15}],
            shipping_flat: 0.0,
            free_shipping_threshold: nil,
            items: %{}

  @default_tiers [{10, 0.05}, {25, 0.10}, {50, 0.15}]

  @doc """
  Creates a new, empty cart.

  See the module documentation for the accepted options. Any option that is
  not supplied falls back to its default value. The returned cart's `:items`
  field is an empty map.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      tax_rate: Keyword.get(opts, :tax_rate, 0.0),
      discount_tiers: Keyword.get(opts, :discount_tiers, @default_tiers),
      shipping_flat: Keyword.get(opts, :shipping_flat, 0.0),
      free_shipping_threshold: Keyword.get(opts, :free_shipping_threshold, nil),
      items: %{}
    }
  end

  @doc """
  Adds `quantity` units of `product_id` at `unit_price` to the cart.

  If the product already exists, its quantity is increased by `quantity`.
  Returns `{:error, :invalid_quantity}` if `quantity` is not a positive
  integer, otherwise `{:ok, cart}`.
  """
  @spec add_item(t(), product_id(), pos_integer(), number()) ::
          {:ok, t()} | {:error, :invalid_quantity}
  def add_item(%__MODULE__{} = cart, product_id, quantity, unit_price)
      when is_integer(quantity) and quantity > 0 do
    price = to_float(unit_price)

    item =
      case Map.get(cart.items, product_id) do
        nil ->
          %{product_id: product_id, quantity: quantity, unit_price: price}

        existing ->
          %{existing | quantity: existing.quantity + quantity, unit_price: price}
      end

    {:ok, %{cart | items: Map.put(cart.items, product_id, item)}}
  end

  def add_item(%__MODULE__{}, _product_id, _quantity, _unit_price) do
    {:error, :invalid_quantity}
  end

  @doc """
  Removes `product_id` from the cart entirely.

  If the product is not present, the cart is returned unchanged.
  """
  @spec remove_item(t(), product_id()) :: t()
  def remove_item(%__MODULE__{} = cart, product_id) do
    %{cart | items: Map.delete(cart.items, product_id)}
  end

  @doc """
  Sets the quantity of an existing item to `quantity`.

  If `quantity` is `0`, the item is removed. If the product is not in the
  cart, returns `{:error, :not_found}`. Returns `{:error, :invalid_quantity}`
  if `quantity` is negative, otherwise `{:ok, cart}`.
  """
  @spec update_quantity(t(), product_id(), non_neg_integer()) ::
          {:ok, t()} | {:error, :not_found | :invalid_quantity}
  def update_quantity(%__MODULE__{}, _product_id, quantity)
      when not is_integer(quantity) or quantity < 0 do
    {:error, :invalid_quantity}
  end

  def update_quantity(%__MODULE__{} = cart, product_id, quantity) do
    case Map.get(cart.items, product_id) do
      nil ->
        {:error, :not_found}

      _existing when quantity == 0 ->
        {:ok, remove_item(cart, product_id)}

      existing ->
        item = %{existing | quantity: quantity}
        {:ok, %{cart | items: Map.put(cart.items, product_id, item)}}
    end
  end

  @doc """
  Computes the totals for the cart.

  Returns a map with `:subtotal`, `:tax`, `:shipping`, `:grand_total`, and
  `:items`. Each entry in `:items` is a map with `:product_id`, `:quantity`,
  `:unit_price`, `:discount_rate`, and `:line_total`.

  Tax is charged on the discounted subtotal only, never on shipping.
  """
  @spec calculate_totals(t()) :: %{
          subtotal: float(),
          tax: float(),
          shipping: float(),
          grand_total: float(),
          items: [map()]
        }
  def calculate_totals(%__MODULE__{} = cart) do
    line_items = Enum.map(Map.values(cart.items), &compute_line(&1, cart.discount_tiers))

    subtotal = Enum.reduce(line_items, 0.0, fn item, acc -> acc + item.line_total end)
    tax = subtotal * cart.tax_rate
    shipping = compute_shipping(cart, line_items, subtotal)

    %{
      subtotal: subtotal,
      tax: tax,
      shipping: shipping,
      grand_total: subtotal + tax + shipping,
      items: line_items
    }
  end

  @spec compute_line(item(), [tier()]) :: map()
  defp compute_line(item, tiers) do
    rate = discount_rate_for(tiers, item.quantity)
    discounted_price = item.unit_price * (1.0 - rate)

    %{
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      discount_rate: rate,
      line_total: discounted_price * item.quantity
    }
  end

  @spec discount_rate_for([tier()], pos_integer()) :: float()
  defp discount_rate_for(tiers, quantity) do
    tiers
    |> Enum.filter(fn {min_qty, _rate} -> min_qty <= quantity end)
    |> Enum.max_by(fn {min_qty, _rate} -> min_qty end, fn -> {0, 0.0} end)
    |> elem(1)
  end

  @spec compute_shipping(t(), [map()], float()) :: float()
  defp compute_shipping(_cart, [], _subtotal), do: 0.0

  defp compute_shipping(cart, _line_items, subtotal) do
    threshold = cart.free_shipping_threshold

    if is_number(threshold) and subtotal >= threshold do
      0.0
    else
      to_float(cart.shipping_flat)
    end
  end

  @spec to_float(number()) :: float()
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_float(value), do: value
end