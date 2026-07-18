  def percentiles(server, name, [_ | _] = q_list) do
    if Enum.all?(q_list, &valid_quantile?/1) do
      GenServer.call(server, {:percentiles, name, Enum.map(q_list, &(&1 * 1.0))})
    else
      {:error, :invalid_quantile}
    end
  end