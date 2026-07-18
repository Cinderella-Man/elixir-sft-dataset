  test "truncation: query!/3 receives the repo module itself and empty params" do
    defmodule EchoRepo do
      def query!(repo, sql, params) do
        send(self(), {:echo_query, repo, sql, params})
        %{rows: [], num_rows: 0}
      end
    end

    DBCleaner.start(:truncation, repo: EchoRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok

    assert_receive {:echo_query, EchoRepo, "TRUNCATE users RESTART IDENTITY CASCADE", []}, 100
    refute_receive {:echo_query, _, _, _}, 50
  end