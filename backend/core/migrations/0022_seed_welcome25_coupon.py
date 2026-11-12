from datetime import datetime, timezone as dt_timezone
from decimal import Decimal

from django.db import migrations
from django.utils import timezone


def seed_welcome25(apps, schema_editor):
    Coupon = apps.get_model('core', 'Coupon')
    now = timezone.now()
    Coupon.objects.update_or_create(
        code='WELCOME25',
        defaults={
            'title': 'Welcome discount',
            'description': 'Get 25% off your booking. Available to every account for up to five paid bookings.',
            'discount_percent': Decimal('25.00'),
            'starts_at': now - timezone.timedelta(days=1),
            'ends_at': datetime(2099, 12, 31, 23, 59, 59, tzinfo=dt_timezone.utc),
            'is_active': True,
            'archived_at': None,
            'owner_user_id': None,
        },
    )


def reverse_seed(apps, schema_editor):
    # Keep the coupon if this migration is rolled back; it may already have been used.
    pass


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0021_merge_booking_checkin_and_court_number'),
    ]

    operations = [
        migrations.RunPython(seed_welcome25, reverse_seed),
    ]
