from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0007_coupon_archived_at'),
    ]

    operations = [
        migrations.AddField(
            model_name='facility',
            name='archived_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
