  @spec invite_member(server(), String.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, :not_found | :conflict | :already_invited}