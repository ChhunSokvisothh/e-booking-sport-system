from decimal import Decimal

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0020_owner_application_mock_payment'),
    ]

    operations = [
        migrations.AlterField(
            model_name='facility',
            name='rating',
            field=models.DecimalField(decimal_places=1, default=Decimal('0.0'), max_digits=2),
        ),
    ]
