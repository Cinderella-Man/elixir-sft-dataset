defmodule Cart do
  @moduledoc """
  An in-memory shopping cart implemented as a pure data structure.

  A `Cart` holds a configurable tax rate and a map of line items keyed by
  product id. There is no database, GenServer, or process involved — every
  operation is a plain function over the struct.

  Line items automatically receive a 10% discount on their unit price when a
  single line's quantity reaches 10 or more. All monetary values are floats.
  """

  @bulk_threshold 10
  @bulk_discount_rate 0.10

  @typedoc "A single line item stored inside the cart."
  @type item :: %{product_id: term(), quantity: pos_integer(), unit_price: float()}

  @typedoc "The cart data structure."
  @type t :: %__MODULE__{tax_rate: float(), items: %{optional(term()) => item()}}

  defstruct tax_rate: 0.0, items: %{}

  @doc """
  Creates a new, empty cart.

  Accepts a `:tax_rate` option as a float (for example `0.08` for 8%). When the
  option is omitted the tax rate defaults to `0.0`.

  ## Examples

      iex> Cart.new(tax_rate: 0.08).tax_rate
      0.08

      iex> Cart.new().items
      %{}

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, 0.0)
    %__MODULE__{tax_rate: tax_rate, items: %{}}
  end

  @doc """
  Adds `quantity` units of `product_id` at `unit_price` to the cart.

  If the product is already present, its quantity is increased by `quantity`.
  Returns `{:error, :invalid_quantity}` when `quantity` is not a positive
  integer.
  """
  @spec add_item(t(), term(), integer(), float()) :: t() | {:error, :invalid_quantity}
  def add_item(_cart, _product_id, quantity, _unit_price)
      when not (is_integer(quantity) and quantity > 0) do
    {:error, :invalid_quantity}
  end

  def add_item(%__MODULE__{items: items} = cart, product_id, quantity, unit_price) do
    item =
      case Map.fetch(items, product_id) do
        {:ok, existing} ->
          %{existing | quantity: existing.quantity + quantity}

        :error ->
          %{product_id: product_id, quantity: quantity, unit_price: unit_price}
      end

    %{cart | items: Map.put(items, product_id, item)}
  end

  @doc """
  Removes `product_id` entirely from the cart.

  When the product is not present the cart is returned unchanged.
  """
  @spec remove_item(t(), term()) :: t()
  def remove_item(%__MODULE__{items: items} = cart, product_id) do
    %{cart | items: Map.delete(items, product_id)}
  end

  @doc """
  Sets the quantity of an existing item to `quantity`.

  A `quantity` of `0` removes the item entirely. Returns
  `{:error, :not_found}` when the product is not in the cart, and
  `{:error, :invalid_quantity}` when `quantity` is negative.
  """
  @spec update_quantity(t(), term(), integer()) ::
          t() | {:error, :not_found} | {:error, :invalid_quantity}
  def update_quantity(_cart, _product_id, quantity)
      when not is_integer(quantity) or quantity < 0 do
    {:error, :invalid_quantity}
  end

  def update_quantity(%__MODULE__{items: items} = cart, product_id, quantity) do
    case Map.fetch(items, product_id) do
      :error ->
        {:error, :not_found}

      {:ok, _item} when quantity == 0 ->
        %{cart | items: Map.delete(items, product_id)}

      {:ok, item} ->
        %{cart | items: Map.put(items, product_id, %{item | quantity: quantity})}
    end
  end

  @doc """
  Computes the totals for the cart.

  Returns a map with `:subtotal`, `:tax`, `:grand_total`, and `:items`. Each
  entry in `:items` is a plain map with `:product_id`, `:quantity`,
  `:unit_price`, `:discount_rate`, and `:line_total`. Line items with a
  quantity of 10 or more receive a 10% discount on the unit price before the
  line total is computed.
  """
  @spec calculate_totals(t()) :: %{
          subtotal: float(),
          tax: float(),
          grand_total: float(),
          items: [
            %{
              product_id: term(),
              quantity: pos_integer(),
              unit_price: float(),
              discount_rate: float(),
              line_total: float()
            }
          ]
        }
  def calculate_totals(%__MODULE__{items: items, tax_rate: tax_rate}) do
    line_items = Enum.map(Map.values(items), &build_line_item/1)
    subtotal = Enum.reduce(line_items, 0.0, fn line, acc -> acc + line.line_total end)
    tax = subtotal * tax_rate

    %{
      subtotal: subtotal,
      tax: tax,
      grand_total: subtotal + tax,
      items: line_items
    }
  end

  @spec build_line_item(item()) :: %{
          product_id: term(),
          quantity: pos_integer(),
          unit_price: float(),
          discount_rate: float(),
          line_total: float()
        }
  defp build_line_item(%{product_id: product_id, quantity: quantity, unit_price: unit_price}) do
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
  defp discount_for(quantity) when quantity >= @bulk_threshold, do: @bulk_discount_rate
  defp discount_for(_quantity), do: 0.0
end