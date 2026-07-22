  def merge(base_config, override_config, opts \\ [])
      when is_map(base_config) and is_map(override_config) do
    resolved = resolve_opts(opts)

    {merged, conflicts} = do_merge(base_config, override_config, [], resolved)

    missing =
      for path <- resolved.required, not path_present?(merged, path) do
        %{type: :missing_required, path: path}
      end

    all = conflicts ++ missing

    case all do
      [] -> {:ok, merged}
      _ -> {:error, Enum.sort_by(all, & &1.path)}
    end
  end