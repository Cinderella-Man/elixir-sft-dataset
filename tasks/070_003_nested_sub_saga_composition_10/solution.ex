  @doc "Appends a leaf step."
  @spec step(t(), atom(), action_fn(), compensate_fn()) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{kind: :leaf, name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end