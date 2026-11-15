# Contributing

## Ground rules

- All work lands on `main`. Feature work gets a folder under `specs/`, never a branch.
- **Single-branch rule**: the Base branch must keep working on its own. If the Unichain branch is broken, Base still settles relief; nothing is marked complete until every required branch has reported in.
- Tests come before implementation. Every behaviour change ships with a test that demonstrates its expected result.

## Setup

```bash
cp .env.example .env      # fill in keys; never commit .env
cd contracts && forge build
cd ../web && npm install
cd ../api && npm install
cd ../ops && npm install
```

## Formatting

One format for every file type, enforced in CI:

```bash
make -C contracts fmt    # forge fmt, 120 columns
npm run format           # prettier, web/ and api/
npm run lint             # eslint, web/ and api/
```

**Enable format on save in your editor** and set your editor to read `.editorconfig`:

- VS Code: install *EditorConfig for VS Code* and *Prettier*, then set
  `"editor.formatOnSave": true` and `"editor.defaultFormatter": "esbenp.prettier-vscode"`.
  For Solidity, set `"[solidity]": { "editor.defaultFormatter": "NomicFoundation.hardhat-solidity" }`.
- JetBrains: *Settings → Tools → Actions on Save → Reformat code*, plus the EditorConfig plugin.

Line endings are pinned to LF by `.gitattributes`. Do not let an editor rewrite files to CRLF; that churn is exactly what `.gitattributes` exists to stop.

## Pre-commit hook

A pre-commit hook runs `forge fmt --check` and `prettier --check` on staged files, so a formatting failure is caught before it reaches CI.

Its purpose is narrow: stop style-only diffs from hiding real changes in review. If the hook fails, run the format commands above and stage the result — do not bypass a failing hook with `--no-verify`.

## Checks before you push

```bash
cd contracts && forge fmt --check && forge test
cd web && npx tsc --noEmit && npm run lint
cd api && npx tsc --noEmit && npm test
```
