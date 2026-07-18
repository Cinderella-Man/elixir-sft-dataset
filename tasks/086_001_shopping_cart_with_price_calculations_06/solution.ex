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