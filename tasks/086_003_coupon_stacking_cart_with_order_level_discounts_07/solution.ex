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