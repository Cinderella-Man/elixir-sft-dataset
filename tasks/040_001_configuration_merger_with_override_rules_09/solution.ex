  @doc """
  Deep-merges `override_config` into `base_config`.

  Returns the merged map directly.
  """
  @spec merge(config_map(), config_map(), opts()) :: config_map()
  def merge(base_config, override_config, opts \\ [])
      when is_map(base_config) and is_map(override_config) do
    resolved_opts = resolve_opts(opts)
    do_merge(base_config, override_config, _current_path = [], resolved_opts)
  end