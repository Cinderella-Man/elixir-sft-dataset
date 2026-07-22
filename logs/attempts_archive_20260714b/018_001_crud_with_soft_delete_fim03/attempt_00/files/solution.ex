  def restore(conn, %{"id" => id}) do
    with {:ok, %Document{} = document} <- Documents.get_document(id, include_deleted: true) do
      {:ok, restored} = Documents.restore_document(document)
      render(conn, :show, document: restored)
    end
  end