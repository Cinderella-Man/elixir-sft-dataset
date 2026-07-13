  test "migration change/0 builds a working entity_transitions table with its index" do
    # Runs the real migration module through the migrator against a fresh,
    # dedicated repo. A gutted change/0 (raise, or missing create table/index)
    # makes this fail.
    Ecto.Migrator.up(
      StateMachine.MigrationRepo,
      20_240_101_000_000,
      Repo.Migrations.CreateEntityTransitions,
      log: false
    )

    # The table exists and every declared column is usable.
    # The migration repo is NOT sandboxed (it is a real file, on purpose — see the
    # header), so a row written here can outlive the test and collide with a
    # concurrently-running eval of this same task. Key the row to this run.
    mid = "m:#{System.pid()}:#{System.unique_integer([:positive])}"

    StateMachine.MigrationRepo.query!(
      "INSERT INTO entity_transitions " <>
        "(entity_id, event, from_state, to_state, version, inserted_at) " <>
        "VALUES (?1, 'confirm', 'pending', 'confirmed', 1, '2026-01-01 00:00:00')",
      [mid]
    )

    %{rows: [[count]]} =
      StateMachine.MigrationRepo.query!(
        "SELECT count(*) FROM entity_transitions WHERE entity_id = ?1",
        [mid]
      )

    assert count == 1

    # The entity_id index the migration declares must also exist.
    %{rows: index_rows} =
      StateMachine.MigrationRepo.query!(
        "SELECT name FROM sqlite_master " <>
          "WHERE type = 'index' AND tbl_name = 'entity_transitions'",
        []
      )

    assert Enum.any?(index_rows, fn [name] ->
             name == "entity_transitions_entity_id_index"
           end)
  end
