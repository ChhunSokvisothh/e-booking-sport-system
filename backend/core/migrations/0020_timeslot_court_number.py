from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0019_profile_venue_fields_and_telegram_link'),
    ]

    operations = [
        migrations.AddField(
            model_name='timeslot',
            name='court_number',
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.RemoveConstraint(
            model_name='timeslot',
            name='unique_slot_per_facility_time',
        ),
        migrations.AddConstraint(
            model_name='timeslot',
            constraint=models.UniqueConstraint(
                fields=('facility', 'start_at', 'end_at', 'court_number'),
                name='unique_slot_per_facility_time_court',
            ),
        ),
    ]
