# Owner application email setup

Owner registration creates a `core.OwnerApplication` row with status `pending` and sends an email notification to the configured administrator. It does **not** grant owner/staff access. An administrator must approve the application in Django Admin; the existing admin action grants staff access on approval.

## Render environment variables

Set these on the Django backend service in Render:

- `OWNER_APPLICATION_ADMIN_EMAIL=visoth079@gmail.com`
- `EMAIL_HOST=smtp.gmail.com`
- `EMAIL_PORT=587`
- `EMAIL_USE_TLS=true`
- `EMAIL_USE_SSL=false`
- `EMAIL_HOST_USER=<the Gmail account used to send notifications>`
- `EMAIL_HOST_PASSWORD=<a Google App Password for that sender account>`
- `DEFAULT_FROM_EMAIL=<the same sender Gmail address>`

Use a Google App Password, not the sender's normal Gmail password. Keep the password only in Render's environment variables; never commit it to Git.

The recipient address is configurable. If `OWNER_APPLICATION_ADMIN_EMAIL` is omitted, it defaults to `visoth079@gmail.com`.

## Admin review

After deployment, sign into `/admin/` with a Django staff/superuser account. Open **Core → Owner applications**, select pending applications, and use **Approve selected owner applications**. Approved users get owner/staff access on their next login.

If SMTP is unavailable, the application is still saved as pending and the backend logs the email error. Check Render logs and verify the SMTP environment variables.

## Database migrations

This change reuses the existing `OwnerApplication` model and does not add or alter database fields, so it does not require a new migration. Do not delete or rewrite already-applied migration files. For deployment, run the project's normal migration command only if other model changes are pending:

```powershell
cd backend
python manage.py showmigrations core
python manage.py migrate
python manage.py check
```
