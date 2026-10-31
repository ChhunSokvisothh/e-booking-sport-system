# In-app owner application review

No email is sent for owner applications. When a prospective venue owner registers, the backend creates an `OwnerApplication` record with `pending` status. The authenticated superadmin reviews the request inside the Flutter app.

## In-app workflow

1. The user submits an owner application.
2. A superadmin signs in and opens Profile → Owner requests.
3. The app loads pending requests from `GET /api/admin/owner-applications/?status=pending`.
4. The superadmin approves or rejects through `POST /api/admin/owner-applications/<id>/review/` with JSON `{"decision":"approve"}` or `{"decision":"reject"}`.

Both endpoints require token authentication and `request.user.is_superuser == True`. Requests from ordinary users and venue owners receive HTTP 403.

Approving grants the applicant staff/owner access. Rejecting marks the application rejected but leaves the account in place. The API reuses the existing `OwnerApplication` model; no new database migration is needed.

## Deployment

Deploy the backend and Flutter changes together. The superadmin should sign out and sign back in (or refresh their session) so the app receives the `is_superuser` flag from `/api/auth/me/`. Ensure the intended administrator account has Django's `is_superuser=True` in the same database used by the Render backend.
