import hashlib

from django.db import migrations, models


def hash_existing_codes(apps, schema_editor):
    LoginAttempt = apps.get_model('core', 'TelegramLoginAttempt')
    for attempt in LoginAttempt.objects.all().iterator():
        attempt.token_hash = hashlib.sha256(attempt.token_hash.encode('utf-8')).hexdigest()
        attempt.used = attempt.status == 'done'
        attempt.save(update_fields=['token_hash', 'used'])


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0010_telegram_identity_login_attempt'),
    ]

    operations = [
        migrations.AddField(
            model_name='telegramloginattempt',
            name='used',
            field=models.BooleanField(default=False),
        ),
        migrations.RenameField(
            model_name='telegramloginattempt',
            old_name='token',
            new_name='token_hash',
        ),
        migrations.RunPython(hash_existing_codes, migrations.RunPython.noop),
    ]
