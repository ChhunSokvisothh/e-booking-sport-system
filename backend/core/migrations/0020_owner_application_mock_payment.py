from decimal import Decimal

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0019_profile_venue_fields_and_telegram_link'),
    ]

    operations = [
        migrations.AddField(
            model_name='ownerapplication',
            name='payment_status',
            field=models.CharField(default='unpaid', max_length=16),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='payment_amount',
            field=models.DecimalField(decimal_places=2, default=Decimal('0.00'), max_digits=8),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='payment_channel',
            field=models.CharField(blank=True, max_length=40),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='payment_provider',
            field=models.CharField(blank=True, max_length=80),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='paid_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
