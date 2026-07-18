  defp check_min_order(%{min_order_total: min}, order_total) do
    if order_total >= min do
      :ok
    else
      {:error, :below_min_order}
    end
  end