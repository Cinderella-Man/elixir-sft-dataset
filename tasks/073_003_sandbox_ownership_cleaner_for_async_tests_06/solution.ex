  defp fetch_repo!(opts) do
    case Keyword.fetch(opts, :repo) do
      {:ok, repo} when is_atom(repo) ->
        repo

      {:ok, other} ->
        raise ArgumentError,
              "expected :repo to be an atom (Ecto repo module), got: #{inspect(other)}"

      :error ->
        raise ArgumentError, ":repo is required. Pass repo: MyApp.Repo in opts"
    end
  end