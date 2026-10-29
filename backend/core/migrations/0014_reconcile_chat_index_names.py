from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0013_align_chat_message_reference'),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.RenameIndex(
                    model_name='chatmessage',
                    old_name='core_chatme_session_76a3ef_idx',
                    new_name='core_chat_m_session_3c4943_idx',
                ),
                migrations.RenameIndex(
                    model_name='chatsession',
                    old_name='core_chatse_user_id_f80ca9_idx',
                    new_name='core_chat_s_user_id_75843c_idx',
                ),
            ],
        ),
    ]
