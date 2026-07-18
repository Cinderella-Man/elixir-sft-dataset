  @spec build_insert_opts(map()) :: keyword()
  defp build_insert_opts(cfg) do
    # An empty conflict_target means "none": the option is omitted rather
    # than passed — Ecto accepts only column lists / fragments there, and
    # on_conflict values like :raise or :nothing need no target at all.
    base =
      if cfg.conflict_target == [] do
        [on_conflict: cfg.on_conflict]
      else
        [on_conflict: cfg.on_conflict, conflict_target: cfg.conflict_target]
      end

    if cfg.returning, do: Keyword.put(base, :returning, true), else: base
  end