# First public repository publication

The intended public location is `FernandoX7/woc-widget`, which is already used by README badges and
the app's Privacy, Support, License, and Source links.

## Why the first push should be a clean snapshot

This project was developed privately before it adopted an independent companion identity. Older
local commits contain a superseded copy of the World of ClaudeCraft crest and a deleted historical
brief with a local working path. Neither is present in the verified current tree, but both would be
retrievable if the complete private history were pushed.

Keep the detailed local `main` history for development and seed the first public repository from a
clean snapshot of its current tree. Do not use `git push --mirror`, `git push --all`, or push local
stashes/auxiliary refs.

## Create the public repository

1. On GitHub, create an empty public repository named `woc-widget` under `FernandoX7`. Do not add a
   generated README, license, or `.gitignore`; the snapshot already contains them.
2. Confirm the local tree is clean and the verification gate passes:

   ```bash
   git switch main
   git status --short
   ./scripts/verify.sh
   ```

3. Export only tracked files from the verified commit and initialize fresh public history:

   ```bash
   EXPORT_DIR="$(mktemp -d)"
   git archive --format=tar HEAD | tar -xf - -C "$EXPORT_DIR"
   cd "$EXPORT_DIR"
   git init -b main
   git add .
   git commit -m "Initial public release"
   git remote add origin git@github.com:FernandoX7/woc-widget.git
   git push -u origin main
   ```

   Use the HTTPS remote instead if preferred:

   ```bash
   git remote set-url origin https://github.com/FernandoX7/woc-widget.git
   ```

4. On GitHub:

   - verify the MIT license and README render correctly;
   - enable Issues and private vulnerability reporting;
   - protect `main` and require the CI workflow;
   - confirm both Actions workflows can run; and
   - add an About description, macOS topic, and project website if desired.

5. Follow [RELEASE.md](RELEASE.md) to create the first signed, notarized, checksummed application
   release. Do not tag or upload an ad-hoc local build.

## Preserving private commit history publicly

Publishing the full local history safely would require a deliberate history rewrite that replaces
the retired binary artwork and removes the obsolete document from every reachable commit. That
changes commit IDs and should be done only after making a backup and reviewing all refs. The clean
snapshot workflow above is safer for a first public release.
