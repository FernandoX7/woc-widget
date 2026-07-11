# WoC Player Count security policy

## Supported versions

Security fixes are applied to `main` and may be identified by a tagged source release. Local builds
do not update automatically: pull the corrected source and run `./install.sh` again. Older commits
may not receive a backport.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability or include exploit details in a discussion.
Use GitHub's private vulnerability reporting for this repository:

<https://github.com/FernandoX7/woc-widget/security/advisories/new>

Include the affected tag or commit hash, macOS version and architecture, impact, reproduction
steps, and a minimal proof of concept when safe. Remove tokens, passwords, wallet material, player
data, and other private information before submitting.

The maintainer will make a best-effort acknowledgement, assessment, and coordinated fix. Please
allow time for a fix and coordinated disclosure before publishing details.

## Scope

In scope are vulnerabilities in this app's networking, decoding, local persistence, notification
actions, launch-at-login integration, export behavior, source-install and optional binary-release
scripts, and repository automation.

Upstream service outages, inaccurate market data, game-account issues, token price movements, and
vulnerabilities in World of ClaudeCraft itself should be reported to the relevant provider unless
the app makes them materially worse.
