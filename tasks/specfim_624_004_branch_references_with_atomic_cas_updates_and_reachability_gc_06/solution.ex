  @spec create_branch(GenServer.server(), String.t(), hash) ::
          {:ok, String.t()} | {:error, :exists | :not_found}