  @spec renew(server(), resource(), owner()) ::
          {:ok, integer()} | {:error, :not_held}