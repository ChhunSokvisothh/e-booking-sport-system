from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0011_reconcile_owner_application_table'),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.AlterModelTable(
                    name='chatsession',
                    table='core_chat_session',
                ),
                migrations.AlterModelTable(
                    name='chatmessage',
                    table='core_chat_message',
                ),
            ],
        ),
    ]
