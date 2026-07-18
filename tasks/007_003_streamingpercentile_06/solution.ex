  def percentile(server, name, q) when is_float(q) or is_integer(q) do
    if valid_quantile?(q) do
      GenServer.call(server, {:percentile, name, q * 1.0})
    else
      {:error, :invalid_quantile}
    end
  end