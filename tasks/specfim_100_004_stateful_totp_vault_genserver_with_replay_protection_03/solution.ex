  @spec register(server(), account_id()) ::
          {:ok, secret()} | {:error, :already_registered}