defmodule Cart do
  @moduledoc """
  An in-memory shopping cart with price calculations.

  `Cart` is a pure data structure: a plain Elixir struct plus functions that
  operate on it. There is no database, no GenServer, and no processes.

  A cart carries a configurable `:tax_rate` (a float such as `0.08` for 8%)
  and a map of `:items` keyed by product id. Each item tracks its quantity
  and per-unit price. Line totals apply a 10% discount when the item's
  quantity is 10 or more.

  All monetary values are plain floats computed with ordinary float
  arithmetic (no `Decimal`) and no rounding is performed.
  """

  @discount_threshold 10
  @discount_rate 0.1

  @typedoc "A single cart line item."
  @type item :: %{
          product_id: term(),
          quantity: pos_integer(),
          unit_price: float()
        }

  @type t :: %__MODULE__{
          tax_rate: float(),
          items: %{optional(term()) => item()}
        }

  defstruct tax_rate: 0.0, items: %{}

  @doc """
  Creates a new, empty cart.

  Accepts a `:tax_rate` option (a float, e.g. `0.08` for 8%). When omitted
  the tax rate defaults to `0.0`.

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

  When the product already exists, its quantity is increased by `quantity`.
  The `unit_price` supplied is recorded for the product.

  Returns `{:ok, cart}` on success, or `{:error, :invalid_quantity}` when
  `quantity` is not a positive integer.
  """
  @spec add_item(t(), term(), integer(), float()) ::
          {:ok, t()} | {:error, :invalid_quantity}
  def add_item(%__MODULE__{} = cart, product_id, quantity, unit_price)
      when is_integer(quantity) and quantity > 0 do
    item =
      case Map.get(cart.items, product_id) do
        nil ->
          %{product_id: product_id, quantity: quantity, unit_price: unit_price}

        existing ->
          %{existing | quantity: existing.quantity + quantity, unit_price: unit_price}
      end

    {:ok, %{cart | items: Map.put(cart.items, product_id, item)}}
  end

  def add_item(%__MODULE__{}, _product_id, _quantity, _unit_price) do
    {:error, :invalid_quantity}
  end

  @doc """
  Removes `product_id` from the cart entirely.

  Returns the updated cart struct directly (not wrapped in `{:ok, _}`). When
  the product is not present, the cart is returned unchanged.
  """
  @spec remove_item(t(), term()) :: t()
  def remove_item(%__MODULE__{} = cart, product_id) do
    %{cart | items: Map.delete(cart.items, product_id)}
  end

  @doc """
  Sets the quantity of an existing item to `quantity`.

  When `quantity` is `0`, the item is removed entirely. Returns `{:ok, cart}`
  on every success path.

  Returns `{:error, :not_found}` when the product is not in the cart, and
  `{:error, :invalid_quantity}` when `quantity` is negative.
  """
  @spec update_quantity(t(), term(), integer()) ::
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
  Computes the cart totals.

  Returns a map with:

    * `:subtotal` — sum of each item's line total (after per-item discounts)
    * `:tax` — `subtotal * tax_rate`
    * `:grand_total` — `subtotal + tax`
    * `:items` — one map per item with `:product_id`, `:quantity`,
      `:unit_price`, `:discount_rate` and `:line_total`

  Items with a quantity of 10 or more receive a `0.1` discount on their unit
  price before the line total is computed; all others receive `0.0`.
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
  def calculate_totals(%__MODULE__{} = cart) do
    items = Enum.map(Map.values(cart.items), &line_item/1)
    subtotal = Enum.reduce(items, 0.0, fn item, acc -> acc + item.line_total end)
    tax = subtotal * cart.tax_rate

    %{
      subtotal: subtotal,
      tax: tax,
      grand_total: subtotal + tax,
      items: items
    }
  end

  @spec line_item(item()) :: %{
          product_id: term(),
          quantity: pos_integer(),
          unit_price: float(),
          discount_rate: float(),
          line_total: float()
        }
  defp line_item(%{quantity: quantity, unit_price: unit_price} = item) do
    discount_rate = if quantity >= @discount_threshold, do: @discount_rate, else: 0.0
    line_total = unit_price * (1.0 - discount_rate) * quantity

    %{
      product_id: item.product_id,
      quantity: quantity,
      unit_price: unit_price,
      discount_rate: discount_rate,
      line_total: line_total
    }
  end
end