  def insert(name, overrides) do
    {struct, assocs} = build_with_assocs(name, overrides)

    case validate(name, struct) do
      :ok ->
        {:ok, MyApp.Repo.insert!(struct)}

      {:error, missing} ->
        Enum.each(assocs, &MyApp.Repo.delete!/1)
        {:error, {:missing_fields, missing}}
    end
  end