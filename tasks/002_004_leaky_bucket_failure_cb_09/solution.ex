  @spec bucket_level(GenServer.server()) :: float()
  def bucket_level(name), do: GenServer.call(name, :bucket_level)