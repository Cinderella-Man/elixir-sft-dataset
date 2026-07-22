  def stage(%__MODULE__{stages: stages} = saga, steps) when is_list(steps) do
    normalized =
      Enum.map(steps, fn {name, action, compensation} ->
        unless is_function(action, 1) and is_function(compensation, 1) do
          raise ArgumentError, "action and compensation must be arity-1 functions"
        end

        %{name: name, action: action, compensation: compensation}
      end)

    %__MODULE__{saga | stages: stages ++ [normalized]}
  end