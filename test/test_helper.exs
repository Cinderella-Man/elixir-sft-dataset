ExUnit.start(exclude: [:skip, :database])

# Only start the repo if database tests are included
if :database in ExUnit.configuration()[:include] do
  {:ok, _} = ElixirBenchmark.Repo.start_link()
  Ecto.Adapters.SQL.Sandbox.mode(ElixirBenchmark.Repo, :manual)
end
