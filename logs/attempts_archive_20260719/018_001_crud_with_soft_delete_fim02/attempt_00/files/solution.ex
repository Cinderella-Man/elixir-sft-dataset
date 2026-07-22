  def get_document(id, opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    query =
      Document
      |> where([d], d.id == ^id)
      |> maybe_exclude_deleted(include_deleted)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      document -> {:ok, document}
    end
  end