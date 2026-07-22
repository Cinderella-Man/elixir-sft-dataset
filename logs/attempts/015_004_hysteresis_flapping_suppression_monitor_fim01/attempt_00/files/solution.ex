  @spec handle_error(term(), map()) :: map()
  defp handle_error(name, %{state: :up} = service) do
    fail_streak = service.fail_streak + 1

    if fail_streak >= service.fail_confirm do
      service.on_transition.(name, :up, :down)
      %{service | state: :down, fail_streak: 0, ok_streak: 0}
    else
      %{service | fail_streak: fail_streak, ok_streak: 0}
    end
  end

  defp handle_error(_name, %{state: :down} = service) do
    %{service | fail_streak: 0, ok_streak: 0}
  end