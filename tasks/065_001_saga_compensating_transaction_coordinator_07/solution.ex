  def step(%__MODULE__{steps: steps} = saga, name, action, compensation)
      when is_function(action, 1) and is_function(compensation, 1) do
    %__MODULE__{
      saga
      | steps: steps ++ [%{name: name, action: action, compensation: compensation}]
    }
  end