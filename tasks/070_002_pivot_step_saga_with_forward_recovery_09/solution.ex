  @doc "Appends a retriable step (retried up to `max_attempts`, never compensated)."
  @spec retriable(t(), atom(), action(), pos_integer()) :: t()
  def retriable(%__MODULE__{} = saga, name, action_fn, max_attempts)
      when is_atom(name) and is_function(action_fn, 1) and is_integer(max_attempts) and
             max_attempts >= 1 do
    entry = %{kind: :retriable, name: name, action: action_fn, max_attempts: max_attempts}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end