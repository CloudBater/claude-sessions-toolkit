---
name: LT-3066-oauth-login
ticket: LT-3066
started: 2026-03-20
updated: 2026-04-17
branch:
  backend: feature/LT-3066-oauth-direct-login
  frontend: feature/LT-3054-sso-frontend
scope: OAuth direct-login endpoint for Google / Microsoft / GitHub — token-based, no redirect
phase: awaiting-merge
status: BE PR #1071 at commit 7a0efcc2 — 9 files / +607 lines, 16/16 tests passing, profile-backfill + serializer flatten landed. FE scope fix committed locally (126c5fece), not pushed. FE error-code routing gap confirmed empirically (not_invited → generic AccessDenied) — follow-up ticket needed.
done:
  - BE endpoint POST /api/oauth/login/ with AnonRateThrottle 10/min
  - oauth_verify.py — verify_google (google-auth), verify_microsoft (PyJWKClient + pyjwt), verify_github (GitHub REST API)
  - Per-provider serializer validation in oauth_direct.py
  - Profile backfill for existing users (case-insensitive email match)
  - 16 unit tests covering success + 4 failure modes per provider
  - Spec at specs origin/main 4ef2498 with FE migration notes section
pending:
  - FE dev to push LT-3054 scope fix (126c5fece) and open PR
  - After both merge: smoke test on dev env with all 3 providers
  - Open follow-up ticket for FE error-code routing (not_invited / invalid_token / provider_unavailable)
blockers: []
key_decisions:
  - Token-type varies by provider — Google uses id_token, Microsoft id_token, GitHub access_token. Don't try to normalize — validate per-provider.
  - No MS tenant whitelist (per org policy). Reject GitHub private-email accounts (invisible signal).
  - No signup_required branch in direct-login — only invited users, same as redirect flow.
  - Audit log gets new provider strings (`oauth_google`, `oauth_microsoft`, `oauth_github`) separate from legacy SSO strings.
files_touched:
  - src/apps/auth_settings/services/oauth_verify.py (NEW)
  - src/apps/auth_settings/serializers/oauth_direct.py (NEW)
  - src/apps/auth_settings/views/oauth_direct.py (NEW)
  - src/apps/auth_settings/urls.py (route)
  - src/apps/auth_settings/tests/test_oauth_direct.py (NEW, 16 tests)
  - specs changes/lt-3066-oauth-direct-login/README.md (spec + FE migration notes)
lessons_learned:
  - PyJWKClient cache must be per-tenant for Microsoft multi-tenant apps
  - GitHub REST API returns `email: null` for private-email users — reject with `private_email` error code
  - AnonRateThrottle needs explicit rate in settings.py, not just class reference
  - Profile backfill must use case-insensitive email match — users sign up with varied casing
resume_hint: |
  Both PRs open, pending review. BE PR #1071 ready to merge; FE PR pending FE dev push.
  Next session: (1) Wait for FE PR to open (2) Merge both (3) Smoke test on dev
  with all 3 providers (4) Open follow-up ticket for FE error-code routing gap.

  To resume BE work: cd backend, git checkout feature/LT-3066-oauth-direct-login
  To verify tests: poetry run pytest src/apps/auth_settings/tests/test_oauth_direct.py

## Timeline

### 2026-04-17

- Pre-push polish round — updated PR body with token-type-per-provider note + profile-backfill behavior + 16-test breakdown
- Empirically confirmed FE error-code routing gap by deactivating my account and re-attempting Google login — BE log shows 400 Bad Request × 2, FE shows generic AccessDenied toast
- Specs at main 4ef2498 — added "Behavior diffs vs v1.14.0 — FE migration notes" section for FE team

### 2026-03-20

- Drafted spec with all 4 open questions resolved (no MS tenant whitelist, reject GitHub private-email, no signup_required, new provider audit strings)
- Created worktree, scaffolded oauth_verify.py with 3 provider functions
- First pass of serializers + view + URL routing
