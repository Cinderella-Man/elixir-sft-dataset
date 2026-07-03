defp apply_event(%{type: :product_registered, name: name, sku: sku}, _nil_state) do
  %{name: name, sku: sku, quantity_on_hand: 0, status: :registered}
end

defp apply_event(%{type: :stock_received, quantity: quantity}, state) do
  %{state | quantity_on_hand: state.quantity_on_hand + quantity}
end

defp apply_event(%{type: :stock_shipped, quantity: quantity}, state) do
  %{state | quantity_on_hand: state.quantity_on_hand - quantity}
end

defp apply_event(%{type: :stock_adjusted, quantity: quantity}, state) do
  %{state | quantity_on_hand: state.quantity_on_hand + quantity}
end