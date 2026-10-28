# Campus profile and gallery support for owner-managed venues.
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0010_owner_application_subscription'),
    ]

    operations = [
        migrations.CreateModel(
            name='Campus',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('owner_user_id', models.UUIDField(db_index=True)),
                ('name', models.CharField(max_length=160)),
                ('description', models.TextField(blank=True)),
                ('address', models.CharField(max_length=255)),
                ('latitude', models.FloatField(default=11.5564)),
                ('longitude', models.FloatField(default=104.9282)),
                ('contact_phone', models.CharField(blank=True, max_length=40)),
                ('contact_email', models.EmailField(blank=True, max_length=254)),
                ('cover_image_url', models.URLField(blank=True)),
                ('opening_hours', models.JSONField(blank=True, default=dict)),
                ('amenities', models.JSONField(blank=True, default=list)),
                ('cancellation_policy', models.TextField(blank=True)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={'ordering': ['name']},
        ),
        migrations.CreateModel(
            name='CampusPhoto',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('image_url', models.URLField()),
                ('caption', models.CharField(blank=True, max_length=160)),
                ('sort_order', models.PositiveIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('campus', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='photos', to='core.campus')),
            ],
            options={'ordering': ['sort_order', 'id']},
        ),
        migrations.AddField(
            model_name='facility',
            name='campus',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='facilities', to='core.campus'),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='contact_email',
            field=models.EmailField(blank=True, max_length=254),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='amenities',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='opening_hours',
            field=models.JSONField(blank=True, default=dict),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='cancellation_policy',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='ownerapplication',
            name='gallery_image_urls',
            field=models.JSONField(blank=True, default=list),
        ),
    ]
