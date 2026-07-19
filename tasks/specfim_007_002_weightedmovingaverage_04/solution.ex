  @spec get(GenServer.server(), term(), :wma | :hma, pos_integer()) ::
          {:ok, float()} | {:error, :no_data | :insufficient_data}