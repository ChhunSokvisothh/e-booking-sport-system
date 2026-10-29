from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0012_align_chat_table_names'),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.AlterField(
                    model_name='chatmessage',
                    name='session',
                    field=models.ForeignKey(
                        db_column='session_id',
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='messages',
                        to='core.chatsession',
                        to_field='session_id',
                    ),
                ),
            ],
        ),
    ]
