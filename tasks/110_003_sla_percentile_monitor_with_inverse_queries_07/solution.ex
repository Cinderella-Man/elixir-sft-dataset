  @spec rank(term, number) :: {:ok, float} | {:error, :empty}
  def rank(name, value) when is_number(value) do
    GenServer.call(@default_name, {:rank, name, value})
  end