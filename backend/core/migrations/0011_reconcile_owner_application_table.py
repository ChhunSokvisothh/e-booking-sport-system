from django.db import migrations


RECONCILE_OWNER_APPLICATION_SQL = """
alter table public.core_owner_application
    add column if not exists venue_name varchar(160) not null default '',
    add column if not exists contact_phone varchar(40) not null default '',
    add column if not exists status varchar(12) not null default 'pending',
    add column if not exists reviewed_at timestamptz,
    add column if not exists created_at timestamptz not null default now();

alter table public.core_owner_application
    alter column user_id type bigint
    using user_id::text::bigint;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conrelid = 'public.core_owner_application'::regclass
          and contype = 'u'
          and conkey = array[
              (select attnum from pg_attribute
               where attrelid = 'public.core_owner_application'::regclass
                 and attname = 'user_id')
          ]::smallint[]
    ) then
        alter table public.core_owner_application
            add constraint core_owner_application_user_id_key unique (user_id);
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'core_owner_application_user_id_fkey'
    ) then
        alter table public.core_owner_application
            add constraint core_owner_application_user_id_fkey
            foreign key (user_id) references public.auth_user(id)
            on delete cascade;
    end if;
end
$$;
"""


class Migration(migrations.Migration):
    dependencies = [
        ('core', '0010_booking_refund_amount_booking_refunded_at_and_more'),
    ]

    operations = [
        migrations.RunSQL(
            sql=RECONCILE_OWNER_APPLICATION_SQL,
            reverse_sql=migrations.RunSQL.noop,
        ),
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.AlterModelTable(
                    name='ownerapplication',
                    table='core_owner_application',
                ),
            ],
        ),
    ]
