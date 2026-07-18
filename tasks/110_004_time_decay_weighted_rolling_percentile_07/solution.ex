  @spec total_weight(term) :: {:ok, float} | {:error, :empty}
  def total_weight(name), do: GenServer.call(@default_name, {:total_weight, name})