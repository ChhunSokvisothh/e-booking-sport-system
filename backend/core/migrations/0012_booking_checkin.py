from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0011_reconcile_owner_application_table'),
        migrations.swappable_dependency('auth.User'),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    sql="""
                    alter table public.core_booking
                        add column if not exists checked_in_at timestamptz;
                    alter table public.core_booking
                        add column if not exists checked_in_by_id bigint;
                    do $$
                    begin
                        if not exists (
                            select 1 from pg_constraint
                            where conname = 'core_booking_checked_in_by_id_fkey'
                        ) then
                            alter table public.core_booking
                                add constraint core_booking_checked_in_by_id_fkey
                                foreign key (checked_in_by_id)
                                references public.auth_user(id) on delete set null;
                        end if;
                    end $$;
                    """,
                    reverse_sql=migrations.RunSQL.noop,
                ),
            ],
            state_operations=[
                migrations.AddField(
                    model_name='booking',
                    name='checked_in_at',
                    field=models.DateTimeField(blank=True, null=True),
                ),
                migrations.AddField(
                    model_name='booking',
                    name='checked_in_by',
                    field=models.ForeignKey(
                        blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL,
                        related_name='booking_checkins', to='auth.user',
                    ),
                ),
            ],
        ),
    ]
