  @spec update_branch(GenServer.server(), String.t(), hash, hash) ::
          {:ok, hash} | {:error, :no_branch | :not_found | :conflict}