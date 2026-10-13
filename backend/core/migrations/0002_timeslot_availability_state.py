from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='timeslot',
            name='availability_state',
            field=models.CharField(
                choices=[('available', 'Available'), ('full', 'Full'), ('closed', 'Closed')],
                db_index=True,
                default='available',
                max_length=12,
            ),
        ),
        migrations.AddField(
            model_name='timeslot',
            name='availability_updated_at',
            field=models.DateTimeField(auto_now=True),
        ),
        migrations.AddIndex(
            model_name='timeslot',
            index=models.Index(fields=['is_open', 'availability_state', 'start_at'], name='core_timeslo_is_ope_f8a4f6_idx'),
        ),
    ]
