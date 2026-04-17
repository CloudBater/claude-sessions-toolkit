---
name: ENG-123-oauth-login
ticket: ENG-123
started: 2026-01-10
updated: 2026-01-19
branch:
  backend: feature/ENG-123-oauth-login
  frontend: feature/ENG-124-oauth-frontend
scope: OAuth direct-login endpoint for Google / Microsoft / GitHub — token-based, no redirect
phase: awaiting-merge
status: Backend PR open at commit abc1234 — 9 files / +607 lines, 16/16 tests passing, profile-backfill + serializer flatten landed. Frontend scope fix committed locally (def5678), not pushed. Frontend error-code routing gap confirmed empirically (not_invited → generic AccessDenied) — follow-up ticket needed.
done:
  - Backend endpoint POST /api/oauth/login/ with anonymous rate throttle 10/min
  - oauth_verify.py — verify_google (google-auth), verify_microsoft (PyJWKClient + pyjwt), verify_github (GitHub REST API)
  - Per-provider serializer validation in oauth_direct.py
  - Profile backfill for existing users (case-insensitive email match)
  - 16 unit tests covering success + 4 failure modes per provider
  - Spec doc updated with frontend migration notes section
pending:
  - Frontend dev to push scope fix (def5678) and open PR
  - After both merge: smoke test on dev env with all 3 providers
  - Open follow-up ticket for frontend error-code routing (not_invited / invalid_token / provider_unavailable)
blockers: []
key_decisions:
  - Token-type varies by provider — Google uses id_token, Microsoft id_token, GitHub access_token. Don't try to normalize — validate per-provider.
  - No Microsoft tenant whitelist (per org policy). Reject GitHub private-email accounts (invisible signal).
  - No signup_required branch in direct-login — only invited users, same as redirect flow.
  - Audit log gets new provider strings (`oauth_google`, `oauth_microsoft`, `oauth_github`) separate from legacy SSO strings.
files_touched:
  - src/apps/auth/services/oauth_verify.py (NEW)
  - src/apps/auth/serializers/oauth_direct.py (NEW)
  - src/apps/auth/views/oauth_direct.py (NEW)
  - src/apps/auth/urls.py (route)
  - src/apps/auth/tests/test_oauth_direct.py (NEW, 16 tests)
  - docs/oauth-login.md (spec + frontend migration notes)
lessons_learned:
  - PyJWKClient cache must be per-tenant for Microsoft multi-tenant apps
  - GitHub REST API returns `email: null` for private-email users — reject with `private_email` error code
  - AnonRateThrottle needs explicit rate in settings.py, not just class reference
  - Profile backfill must use case-insensitive email match — users sign up with varied casing
resume_hint: |
  Both PRs open, pending review. Backend PR ready to merge; frontend PR pending dev push.
  Next session: (1) Wait for frontend PR to open (2) Merge both (3) Smoke test on dev
  with all 3 providers (4) Open follow-up ticket for frontend error-code routing gap.

  To resume backend work: cd backend, git checkout feature/ENG-123-oauth-login
  To verify tests: poetry run pytest src/apps/auth/tests/test_oauth_direct.py

## Timeline

### 2026-01-19

- Pre-push polish round — updated PR body with token-type-per-provider note + profile-backfill behavior + 16-test breakdown
- Empirically confirmed frontend error-code routing gap by deactivating test account and re-attempting Google login — backend log shows 400 Bad Request × 2, frontend shows generic AccessDenied toast
- Spec updated with "Behavior diffs — frontend migration notes" section for frontend team

### 2026-01-10

- Drafted spec with all 4 open questions resolved (no Microsoft tenant whitelist, reject GitHub private-email, no signup_required, new provider audit strings)
- Created worktree, scaffolded oauth_verify.py with 3 provider functions
- First pass of serializers + view + URL routing
