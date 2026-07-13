# Repository Layout

The root stays focused on user-facing entry points and top-level product concepts. Installer internals live under `installer/` so folders like `guidance`, `pins`, and `migrations` do not look like unrelated top-level products.

```text
AGENTS.md
README.md
install.sh
update.sh
doctor.sh
validate.sh
packs/
  <pack-name>.pack       # declarative skill, dependency, and guidance selection
skills/
  <skill-name>/
    SKILL.md
    agents/openai.yaml
    assets/              # optional reviewed runtime templates
    scripts/             # optional skill-scoped helpers
installer/
  lib/
    common.sh            # shared hashing and pack parsing helpers
  guidance/
    git-safety.md        # source for the installer-managed global guidance block
  evals/
    routing.tsv          # positive and adjacent-negative trigger fixtures
    workflow-safety.tsv  # mutation-safety forward-test fixtures
  migrations/
    legacy-skill-hashes.tsv # approved upgrade hashes from pre-manifest releases
  pins/
    cli.env              # exact managed Codex/devcontainer versions
tests/
  run.sh
  test-installer.sh
  test-ee-toolkit.sh
  test-ralph-safety.sh
  test-ralph-pinned-integration.sh
vendor/
  equalexperts/
    llm-toolkit/         # upstream git submodule; do not copy into skills
docs/
  <topic>.md
```

## Placement Rules

- Global Codex skills live under `skills/<skill-name>/`.
- Pack manifests live under `packs/<pack-name>.pack`.
- Human documentation lives in `README.md` and `docs/`.
- Installer implementation details live under `installer/`.
- External reusable toolkits should be git submodules under `vendor/`.
- Large third-party rule sets should be referenced or linked, not copied into skill bodies.
