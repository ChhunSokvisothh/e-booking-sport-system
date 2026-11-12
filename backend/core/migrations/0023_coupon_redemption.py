from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0022_seed_welcome25_coupon'),
    ]

    operations = [
        migrations.CreateModel(
            name='CouponRedemption',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('user_id', models.UUIDField(db_index=True)),
                ('coupon_code', models.CharField(db_index=True, max_length=40)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={'ordering': ['-created_at']},
        ),
        migrations.AddIndex(
            model_name='couponredemption',
            index=models.Index(fields=['user_id', 'coupon_code', 'created_at'], name='core_coupon_user_code_idx'),
        ),
    ]
