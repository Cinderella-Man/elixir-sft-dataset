  @spec list_invitations(server(), String.t()) ::
          {:ok, [String.t()]} | {:error, :not_found}