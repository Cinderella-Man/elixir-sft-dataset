  @spec add_member_safe(server(), String.t(), String.t(), integer()) ::
          {:ok, String.t(), non_neg_integer()}
          | {:error, :not_found | :stale | :conflict}