from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0004_facility_rating_image_url'),
    ]

    operations = [
        migrations.AddField(
            model_name='timeslot',
            name='reservation_hold_until',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='timeslot',
            name='slot_version',
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.AddField(
            model_name='booking',
            name='booking_source',
            field=models.CharField(
                choices=[('manual', 'Manual App Booking'), ('chatbot', 'Chatbot Booking')],
                default='manual',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='booking',
            name='chatbot_session_id',
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.AddIndex(
            model_name='booking',
            index=models.Index(fields=['booking_source', 'chatbot_session_id'], name='core_book_src_chat_idx'),
        ),
    ]
