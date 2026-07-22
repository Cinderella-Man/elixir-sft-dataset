  @doc """
  Appends a fan-out map stage. Its input must be a list; `fun` is applied to
  each element concurrently. Option `:max_concurrency` bounds parallelism.
  """
  @spec map_stage(t(), atom(), stage_fun(), keyword()) :: t()
  def map_stage(%__MODULE__{stages: stages} = pipeline, name, fun, opts \\ [])
      when is_atom(name) and is_function(fun, 1) and is_list(opts) do
    mc = Keyword.get(opts, :max_concurrency, nil)
    %__MODULE__{pipeline | stages: stages ++ [{:map, name, fun, mc}]}
  end