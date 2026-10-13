from decimal import Decimal

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0003_rename_core_timeslo_is_ope_f8a4f6_idx_core_timesl_is_open_64126f_idx'),
    ]

    operations = [
        migrations.AddField(
            model_name='facility',
            name='rating',
            field=models.DecimalField(decimal_places=1, default=Decimal('4.5'), max_digits=2),
        ),
        migrations.AddField(
            model_name='facility',
            name='image_url',
            field=models.URLField(blank=True),
        ),
    ]
