  @spec handle_ok(term(), map()) :: map()
  defp handle_ok(name, %{state: :down} = service) do
    ok_streak = service.ok_streak + 1

    if ok_streak >= service.ok_confirm do
      service.on_transition.(name, :down, :up)
      %{service | state: :up, ok_streak: 0, fail_streak: 0}
    else
      %{service | ok_streak: ok_streak, fail_streak: 0}
    end
  end

  defp handle_ok(_name, %{state: :up} = service) do
    %{service | ok_streak: 0, fail_streak: 0}
  end