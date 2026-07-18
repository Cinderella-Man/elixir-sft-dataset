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