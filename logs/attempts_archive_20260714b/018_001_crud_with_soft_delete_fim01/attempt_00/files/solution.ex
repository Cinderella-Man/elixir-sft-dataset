  def soft_delete_document(%Document{deleted_at: deleted_at} = document)
      when not is_nil(deleted_at) do
    {:ok, document}
  end

  def soft_delete_document(%Document{} = document) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    document
    |> Document.soft_delete_changeset(%{deleted_at: now})
    |> Repo.update()
  end