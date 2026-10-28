# Generated for the campus owner program.
import django.db.models.deletion
from decimal import Decimal
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0009_rename_core_book_src_chat_idx_core_bookin_booking_6218b4_idx_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='OwnerApplication',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('user_id', models.UUIDField(db_index=True)),
                ('campus_name', models.CharField(max_length=160)),
                ('description', models.TextField()),
                ('location_name', models.CharField(max_length=255)),
                ('latitude', models.FloatField(default=11.5564)),
                ('longitude', models.FloatField(default=104.9282)),
                ('sport_type', models.CharField(choices=[('football', 'Football'), ('billiard', 'Billiard'), ('pickleball', 'Pickleball'), ('volleyball', 'Volleyball'), ('basketball', 'Basketball'), ('futsal', 'Futsal'), ('tennis', 'Tennis'), ('badminton', 'Badminton')], max_length=32)),
                ('is_indoor', models.BooleanField(default=False)),
                ('base_price_per_hour', models.DecimalField(decimal_places=2, max_digits=10)),
                ('image_url', models.URLField(blank=True)),
                ('contact_phone', models.CharField(blank=True, max_length=40)),
                ('status', models.CharField(choices=[('pending', 'Pending review'), ('under_review', 'Under review'), ('approved', 'Approved - awaiting payment'), ('rejected', 'Rejected')], default='pending', max_length=20)),
                ('admin_note', models.TextField(blank=True)),
                ('reviewed_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('reviewed_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='reviewed_owner_applications', to=settings.AUTH_USER_MODEL)),
            ],
            options={'ordering': ['-created_at']},
        ),
        migrations.CreateModel(
            name='OwnerSubscription',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('user_id', models.UUIDField(db_index=True)),
                ('plan', models.CharField(default='monthly', max_length=20)),
                ('amount', models.DecimalField(decimal_places=2, default=Decimal('20.00'), max_digits=8)),
                ('currency', models.CharField(default='USD', max_length=3)),
                ('status', models.CharField(choices=[('pending_payment', 'Pending payment'), ('active', 'Active'), ('expired', 'Expired'), ('cancelled', 'Cancelled')], default='pending_payment', max_length=20)),
                ('payment_reference', models.CharField(blank=True, db_index=True, max_length=120)),
                ('started_at', models.DateTimeField(blank=True, null=True)),
                ('expires_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('application', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='subscriptions', to='core.ownerapplication')),
            ],
            options={'ordering': ['-created_at']},
        ),
    ]
