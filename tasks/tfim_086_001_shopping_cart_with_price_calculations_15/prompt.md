# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule CartTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Cart creation
  # -------------------------------------------------------

  test "new/0 creates an empty cart with default tax rate" do
    cart = Cart.new()
    assert cart.tax_rate == 0.0
    assert cart.items == %{}
  end

  test "new/1 accepts a custom tax rate" do
    cart = Cart.new(tax_rate: 0.1)
    assert cart.tax_rate == 0.1
  end

  # -------------------------------------------------------
  # add_item
  # -------------------------------------------------------

  test "add_item adds a new product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    totals = Cart.calculate_totals(cart)
    assert length(totals.items) == 1
    [item] = totals.items
    assert item.product_id == "prod:1"
    assert item.quantity == 2
    assert item.unit_price == 5.0
  end

  test "add_item accumulates quantity for existing product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 3, 5.0)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 4, 5.0)
    totals = Cart.calculate_totals(cart)
    [item] = totals.items
    assert item.quantity == 7
  end

  test "add_item rejects zero quantity" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", 0, 5.0)
  end

  test "add_item rejects negative quantity" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", -1, 5.0)
  end

  # -------------------------------------------------------
  # remove_item
  # -------------------------------------------------------

  test "remove_item removes an existing product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    cart = Cart.remove_item(cart, "prod:1")
    totals = Cart.calculate_totals(cart)
    assert totals.items == []
  end

  test "remove_item is a no-op for unknown product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    cart2 = Cart.remove_item(cart, "prod:999")
    assert Cart.calculate_totals(cart2).items == Cart.calculate_totals(cart).items
  end

  # -------------------------------------------------------
  # update_quantity
  # -------------------------------------------------------

  test "update_quantity changes the quantity of an item" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    {:ok, cart} = Cart.update_quantity(cart, "prod:1", 8)
    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 8
  end

  test "update_quantity to 0 removes the item" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    {:ok, cart} = Cart.update_quantity(cart, "prod:1", 0)
    assert Cart.calculate_totals(cart).items == []
  end

  test "update_quantity returns error for unknown product" do
    cart = Cart.new()
    assert {:error, :not_found} = Cart.update_quantity(cart, "prod:999", 5)
  end

  test "update_quantity rejects negative quantity" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    assert {:error, :invalid_quantity} = Cart.update_quantity(cart, "prod:1", -3)
  end

  # -------------------------------------------------------
  # Discount threshold
  # -------------------------------------------------------

  test "9 items: no discount applied" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 9, 10.0)
    totals = Cart.calculate_totals(cart)
    [item] = totals.items
    assert item.discount_rate == 0.0
    assert_in_delta item.line_total, 90.0, 0.001
    assert_in_delta totals.subtotal, 90.0, 0.001
  end

  test "10 items: 10% discount applied" do
    # TODO
  end

  test "discount threshold is per line item, not per cart" do
    cart = Cart.new()
    # discounted
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    # not discounted
    {:ok, cart} = Cart.add_item(cart, "prod:2", 3, 20.0)
    totals = Cart.calculate_totals(cart)

    discounted = Enum.find(totals.items, &(&1.product_id == "prod:1"))
    full_price = Enum.find(totals.items, &(&1.product_id == "prod:2"))

    assert discounted.discount_rate == 0.1
    assert full_price.discount_rate == 0.0
    assert_in_delta discounted.line_total, 90.0, 0.001
    assert_in_delta full_price.line_total, 60.0, 0.001
  end

  # -------------------------------------------------------
  # Tax calculation
  # -------------------------------------------------------

  test "tax is applied on top of the discounted subtotal" do
    cart = Cart.new(tax_rate: 0.1)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    # line_total = 90.0, tax = 9.0, grand_total = 99.0
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 90.0, 0.001
    assert_in_delta totals.tax, 9.0, 0.001
    assert_in_delta totals.grand_total, 99.0, 0.001
  end

  test "zero tax rate produces no tax" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 50.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, totals.subtotal, 0.001
  end

  # -------------------------------------------------------
  # Empty cart
  # -------------------------------------------------------

  test "calculate_totals on empty cart returns all zeros" do
    cart = Cart.new(tax_rate: 0.08)
    totals = Cart.calculate_totals(cart)
    assert totals.items == []
    assert_in_delta totals.subtotal, 0.0, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001
  end

  # -------------------------------------------------------
  # Multi-step scenario
  # -------------------------------------------------------

  test "full lifecycle: add, update, remove, recalculate" do
    cart = Cart.new(tax_rate: 0.05)

    # 100.0, no discount
    {:ok, cart} = Cart.add_item(cart, "a", 5, 20.0)
    # 72.0 after 10% discount
    {:ok, cart} = Cart.add_item(cart, "b", 10, 8.0)
    # 50.0, no discount
    {:ok, cart} = Cart.add_item(cart, "c", 1, 50.0)

    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 222.0, 0.001

    # Bump "a" over the discount threshold
    # now 180.0 after discount
    {:ok, cart} = Cart.update_quantity(cart, "a", 10)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 302.0, 0.001

    # Remove "c"
    cart = Cart.remove_item(cart, "c")
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 252.0, 0.001
    assert_in_delta totals.tax, 252.0 * 0.05, 0.001
    assert_in_delta totals.grand_total, 252.0 * 1.05, 0.001
  end

  test "add_item rejects a non-integer quantity" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", 2.5, 5.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", "3", 5.0)
    assert Cart.calculate_totals(cart).items == []
  end

  test "discounted line echoes the raw unit price, not the discounted price" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.product_id == "prod:1"
    assert item.quantity == 10
    assert item.unit_price == 10.0
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001
  end

  test "update_quantity to 0 for an unknown product returns not_found" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    assert {:error, :not_found} = Cart.update_quantity(cart, "prod:999", 0)
    [item] = Cart.calculate_totals(cart).items
    assert item.product_id == "prod:1"
  end

  test "remove_item returns a bare cart struct for both hit and miss" do
    cart = Cart.new(tax_rate: 0.08)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)

    missed = Cart.remove_item(cart, "prod:999")
    refute match?({:ok, _}, missed)
    assert is_struct(missed, Cart)
    assert missed.tax_rate == 0.08

    hit = Cart.remove_item(cart, "prod:1")
    refute match?({:ok, _}, hit)
    assert is_struct(hit, Cart)
    assert Cart.calculate_totals(hit).items == []
  end

  test "accumulated adds crossing the threshold earn the discount" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 5, 10.0)
    [before] = Cart.calculate_totals(cart).items
    assert before.discount_rate == 0.0

    {:ok, cart} = Cart.add_item(cart, "prod:1", 5, 10.0)
    totals = Cart.calculate_totals(cart)
    assert length(totals.items) == 1
    [item] = totals.items
    assert item.quantity == 10
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001
    assert_in_delta totals.subtotal, 90.0, 0.001
  end

  test "update_quantity back below the threshold drops the discount" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 11, 10.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 99.0, 0.001

    {:ok, cart} = Cart.update_quantity(cart, "prod:1", 9)
    [item] = Cart.calculate_totals(cart).items
    assert item.discount_rate == 0.0
    assert_in_delta item.line_total, 90.0, 0.001
  end
end
```
