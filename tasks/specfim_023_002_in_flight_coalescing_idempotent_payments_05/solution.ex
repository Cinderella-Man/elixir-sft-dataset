  @spec get_payment(GenServer.server(), String.t()) ::
          {:ok, response()} | {:error, :not_found}