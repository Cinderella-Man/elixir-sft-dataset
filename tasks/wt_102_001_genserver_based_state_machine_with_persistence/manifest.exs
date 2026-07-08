# Repo-only tier: the harness injects the kit-provided StateMachine.Repo
# (real SQLite, bundle migration applied) — no web layer to infer from.
%{
  archetype: :ecto_repo,
  prefix: "StateMachine",
  otp_app: :state_machine,
  db: :sqlite
}
