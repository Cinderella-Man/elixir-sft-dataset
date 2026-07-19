  @spec get_object(server(), String.t(), String.t()) ::
          {:ok, %{data: binary(), size: non_neg_integer(), last_modified: DateTime.t()}}
          | {:error, :bucket_not_found | :not_found}