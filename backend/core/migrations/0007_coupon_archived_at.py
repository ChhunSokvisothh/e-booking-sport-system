from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0006_coupon_and_booking_discount'),
    ]

    operations = [
        migrations.AddField(
            model_name='coupon',
            name='archived_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
