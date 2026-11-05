from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0018_user_profile'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='facility',
            name='gallery_image_urls',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name='facility',
            name='amenities',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name='facility',
            name='opening_hours',
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name='facility',
            name='contact_phone',
            field=models.CharField(blank=True, max_length=30),
        ),
        migrations.AddField(
            model_name='facility',
            name='website_url',
            field=models.URLField(blank=True),
        ),
        migrations.AddField(
            model_name='facility',
            name='surface_type',
            field=models.CharField(blank=True, max_length=100),
        ),
        migrations.AddField(
            model_name='facility',
            name='cancellation_policy',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='facility',
            name='court_count',
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.AddField(
            model_name='userprofile',
            name='avatar_path',
            field=models.CharField(blank=True, default='', max_length=500),
        ),
        migrations.CreateModel(
            name='TelegramLinkAttempt',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('token_hash', models.CharField(max_length=64, unique=True)),
                ('expires_at', models.DateTimeField(db_index=True)),
                ('used', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='telegram_link_attempts',
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={'ordering': ['-created_at']},
        ),
    ]
