  @spec decline_invite(server(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found | :no_invitation}