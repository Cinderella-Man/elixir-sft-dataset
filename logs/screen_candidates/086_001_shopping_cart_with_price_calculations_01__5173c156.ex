defmodule Cart do
  @moduledoc """
  An in-memory shopping cart with price calculations.

  `Cart` is a pure data structure: no database, no GenServer, and no
  processes. A cart holds a configurable tax rate and a map of items keyed
  by product id. All monetary values are floats.

  Line items with a quantity of 10 or more automatically receive a 10%
  discount on their unit price before the line total is computed.
  """

  @discount_threshold 10
  @discount_rate 0.10

  @type product_id :: term()

  @type item :: %{
          product_id: product_id(),
          quantity: pos_integer(),
          unit_price: float()
        }

  @type t :: %__MODULE__{
          tax_rate: float(),
          items: %{optional(product_id()) => item()}
        }

  defstruct tax_rate: 0.0, items: %{}

  @doc """
  Creates a new, empty cart.

  Accepts a `:tax_rate` option as a float (for example `0.08` for 8%).
  When not provided, the tax rate defaults to `0.0`.

  ## Examples

      iex> Cart.new().tax_rate
      0.0

      iex> Cart.new(tax_rate: 0.08).tax_rate
      0.08

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, 0.0)
    %__MODULE__{tax_rate: tax_rate, items: %{}}
  end

  @doc """
  Adds `quantity` units of `product_id` at `unit_price` to the cart.

  If the product already exists in the cart, its quantity is increased by
  `quantity` (the stored `unit_price` is updated to the given value).

  Returns `{:error, :invalid_quantity}` if `quantity` is not a positive
  integer.
  """
  @spec add_item(t(), product_id(), integer(), float()) ::
          t() | {:error, :invalid_quantity}
  def add_item(%__MODULE__{} = cart, product_id, quantity, unit_price)
      when is_integer(quantity) and quantity > 0 do
    item =
      case Map.get(cart.items, product_id) do
        nil ->
          %{product_id: product_id, quantity: quantity, unit_price: unit_price}

        %{quantity: existing} = current ->
          %{current | quantity: existing + quantity, unit_price: unit_price}
      end

    %{cart | items: Map.put(cart.items, product_id, item)}
  end

  def add_item(%__MODULE__{}, _product_id, _quantity, _unit_price) do
    {:error, :invalid_quantity}
  end

  @doc """
  Removes `product_id` entirely from the cart.

  If the product is not in the cart, the cart is returned unchanged.
  """
  @spec remove_item(t(), product_id()) :: t()
  def remove_item(%__MODULE__{} = cart, product_id) do
    %{cart | items: Map.delete(cart.items, product_id)}
  end

  @doc """
  Sets the quantity of an existing item to `quantity`.

  If `quantity` is `0`, the item is removed entirely. Returns
  `{:error, :not_found}` if the product is not in the cart, and
  `{:error, :invalid_quantity}` if `quantity` is negative or not an
  integer.
  """
  @spec update_quantity(t(), product_id(), integer()) ::
          t() | {:error, :not_found} | {:error, :invalid_quantity}
  def update_quantity(%__MODULE__{}, _product_id, quantity)
      when not is_integer(quantity) or quantity < 0 do
    {:error, :invalid_quantity}
  end

  def update_quantity(%__MODULE__{} = cart, product_id, quantity) do
    case Map.get(cart.items, product_id) do
      nil ->
        {:error, :not_found}

      _item when quantity == 0 ->
        remove_item(cart, product_id)

      item ->
        updated = %{item | quantity: quantity}
        %{cart | items: Map.put(cart.items, product_id, updated)}
    end
  end

  @doc """
  Calculates the totals for the cart.

  Returns a map with:

    * `:subtotal` — sum of each item's discounted line total;
    * `:tax` — `subtotal * tax_rate`;
    * `:grand_total` — `subtotal + tax`;
    * `:items` — a list of per-item maps, each with `:product_id`,
      `:quantity`, `:unit_price`, `:discount_rate`, and `:line_total`.

  Items with a quantity of 10 or more receive a 10% discount on their unit
  price before the line total is computed.
  """
  @spec calculate_totals(t()) :: %{
          subtotal: float(),
          tax: float(),
          grand_total: float(),
          items: [
            %{
              product_id: product_id(),
              quantity: pos_integer(),
              unit_price: float(),
              discount_rate: float(),
              line_total: float()
            }
          ]
        }
  def calculate_totals(%__MODULE__{} = cart) do
    items =
      cart.items
      |> Map.values()
      |> Enum.map(&line/1)

    subtotal = Enum.reduce(items, 0.0, fn item, acc -> acc + item.line_total end)
    tax = subtotal * cart.tax_rate

    %{
      subtotal: subtotal,
      tax: tax,
      grand_total: subtotal + tax,
      items: items
    }
  end

  @spec line(item()) :: %{
          product_id: product_id(),
          quantity: pos_integer(),
          unit_price: float(),
          discount_rate: float(),
          line_total: float()
        }
  defp line(%{product_id: product_id, quantity: quantity, unit_price: unit_price}) do
    discount_rate = discount_for(quantity)
    discounted_price = unit_price * (1.0 - discount_rate)

    %{
      product_id: product_id,
      quantity: quantity,
      unit_price: unit_price,
      discount_rate: discount_rate,
      line_total: discounted_price * quantity
    }
  end

  @spec discount_for(pos_integer()) :: float()
  defp discount_for(quantity) when quantity >= @discount_threshold, do: @discount_rate
  defp discount_for(_quantity), do: 0.0
end