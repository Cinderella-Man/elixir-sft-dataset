  @spec list_objects(server(), String.t()) ::
          {:ok, [%{key: String.t(), size: non_neg_integer(), last_modified: DateTime.t()}]}
          | {:error, :bucket_not_found}