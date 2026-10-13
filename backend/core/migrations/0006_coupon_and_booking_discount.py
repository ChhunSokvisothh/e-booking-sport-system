from decimal import Decimal

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0005_timeslot_audit_booking_source_chatbot'),
    ]

    operations = [
        migrations.AddField(
            model_name='booking',
            name='coupon_code',
            field=models.CharField(blank=True, max_length=40),
        ),
        migrations.AddField(
            model_name='booking',
            name='coupon_discount',
            field=models.DecimalField(decimal_places=2, default=Decimal('0.00'), max_digits=10),
        ),
        migrations.AddIndex(
            model_name='booking',
            index=models.Index(fields=['coupon_code'], name='core_booking_coupon_idx'),
        ),
        migrations.CreateModel(
            name='Coupon',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('code', models.CharField(max_length=40, unique=True)),
                ('title', models.CharField(blank=True, max_length=120)),
                ('description', models.CharField(blank=True, max_length=255)),
                ('discount_percent', models.DecimalField(decimal_places=2, max_digits=5)),
                ('starts_at', models.DateTimeField()),
                ('ends_at', models.DateTimeField()),
                ('is_active', models.BooleanField(default=True)),
                ('owner_user_id', models.UUIDField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='coupon',
            index=models.Index(fields=['code'], name='core_coupon_code_idx'),
        ),
        migrations.AddIndex(
            model_name='coupon',
            index=models.Index(fields=['is_active', 'starts_at', 'ends_at'], name='core_coupon_active_window_idx'),
        ),
    ]
