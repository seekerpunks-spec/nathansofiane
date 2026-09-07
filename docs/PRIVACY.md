# CyberSeeker privacy notice — publication draft

Last updated: 7 September 2026.

CyberSeeker uses a Solana wallet address as the account identifier. The game
stores gameplay balances and progression, public profile fields (friend code,
display name and avatar), friendships and crew membership, purchases and
provider verification references, security/session records, economy audit
records, and product analytics needed to operate and protect the game.

CyberSeeker does not sell player data. The current repository does not enable a
real advertising, payment, NFT-indexing or SKR-settlement provider. Before any
provider is enabled, this notice must name that provider, its purpose, the data
sent to it, and its own privacy terms.

Default server retention is 90 days for analytics, 730 days for economy audit,
365 days for archived live-ops records, and 30 days for crew activity and
hashed deletion proofs. Production may configure these periods within the
validated server limits and must publish the chosen values.

An authenticated player can request a portable copy through
`GET /account/export`. Account deletion uses `POST /account/delete` with the
explicit confirmation `DELETE CYBERSEEKER ACCOUNT`. Deletion removes the player
and linked records transactionally, scrubs non-relational archives, transfers
crew ownership when needed, and invalidates access to protected player routes.
A short-lived pseudonymous hash-only proof is retained to make network retries
idempotent. This hash is not anonymous: a known wallet address can be matched.

Public social surfaces expose a stable derived friend code, display name, avatar,
progression and game activity; they do not expose the wallet address. Crew chat
only accepts predefined phrases and stores no free-form message text.

This file is a technically accurate draft, not legal advice. The publisher must
add its legal entity, contact email, hosting region, age policy and public URL
before submission.
