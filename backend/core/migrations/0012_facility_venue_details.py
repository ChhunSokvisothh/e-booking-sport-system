from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0009_rename_core_book_src_chat_idx_core_bookin_booking_6218b4_idx_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='facility',
            name='gallery_image_urls',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name='facility',
            name='amenities',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name='facility',
            name='opening_hours',
            field=models.JSONField(blank=True, default=dict),
        ),
        migrations.AddField(
            model_name='facility',
            name='contact_phone',
            field=models.CharField(blank=True, max_length=40),
        ),
        migrations.AddField(
            model_name='facility',
            name='website_url',
            field=models.URLField(blank=True),
        ),
        migrations.AddField(
            model_name='facility',
            name='surface_type',
            field=models.CharField(blank=True, max_length=80),
        ),
        migrations.AddField(
            model_name='facility',
            name='cancellation_policy',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='facility',
            name='court_count',
            field=models.PositiveSmallIntegerField(default=1),
        ),
    ]
