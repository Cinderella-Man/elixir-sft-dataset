def stage(%__MODULE__{stages: stages} = pipeline, name, fun, opts \\ [])
    when is_atom(name) and is_function(fun, 1) and is_list(opts) do
  retries = Keyword.get(opts, :retries, 0)
  backoff = Keyword.get(opts, :backoff_ms, 0)
  %__MODULE__{pipeline | stages: stages ++ [{name, fun, retries, backoff}]}
end