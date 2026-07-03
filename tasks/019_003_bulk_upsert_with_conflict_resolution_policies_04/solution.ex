  defp validate(attrs) do
    errors =
      %{}
      |> put_sku_error(attrs)
      |> put_name_error(attrs)
      |> put_price_error(attrs)
      |> put_qty_error(attrs)

    if map_size(errors) == 0 do
      {:ok,
       %{
         sku: attrs["sku"],
         name: attrs["name"],
         price: attrs["price"],
         qty: normalize_qty(Map.get(attrs, "qty"))
       }}
    else
      {:error, errors}
    end
  end