from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0017_telegram_invoice_delivery'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='UserProfile',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('display_name', models.CharField(blank=True, max_length=100)),
                ('preferred_city', models.CharField(blank=True, default='Phnom Penh', max_length=100)),
                ('favorite_sport', models.CharField(blank=True, default='football', max_length=32)),
                ('push_notifications', models.BooleanField(default=True)),
                ('special_offers', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='profile', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'core_user_profile'},
        ),
    ]
