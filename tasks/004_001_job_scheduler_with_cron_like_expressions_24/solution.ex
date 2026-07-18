  # Returns 0 = Sunday, 1 = Monday, … 6 = Saturday to match standard cron.
  defp day_of_week(dt) do
    # Elixir's Date.day_of_week/1 returns 1 = Monday … 7 = Sunday.
    case Date.day_of_week(dt) do
      7 -> 0
      n -> n
    end
  end