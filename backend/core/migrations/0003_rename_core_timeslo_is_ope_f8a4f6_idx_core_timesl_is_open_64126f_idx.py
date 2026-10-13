from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0002_timeslot_availability_state'),
    ]

    operations = [
        migrations.RenameIndex(
            model_name='timeslot',
            new_name='core_timesl_is_open_64126f_idx',
            old_name='core_timeslo_is_ope_f8a4f6_idx',
        ),
    ]
