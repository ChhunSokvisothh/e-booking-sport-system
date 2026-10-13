from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = 'Create or update an owner account (is_staff=True) for owner console login.'

    def add_arguments(self, parser):
        parser.add_argument('--email', required=True, help='Owner email')
        parser.add_argument('--password', required=True, help='Owner password (min 8 chars)')

    def handle(self, *args, **options):
        email = (options['email'] or '').strip().lower()
        password = (options['password'] or '').strip()

        if not email:
            raise CommandError('Email is required')
        if len(password) < 8:
            raise CommandError('Password must be at least 8 characters')

        User = get_user_model()
        user = User.objects.filter(username=email).first()

        if user is None:
            user = User.objects.create_user(username=email, email=email, password=password)
            self.stdout.write(self.style.SUCCESS(f'Created owner account for {email}'))
        else:
            user.set_password(password)
            self.stdout.write(self.style.WARNING(f'Updated password for existing account {email}'))

        user.is_staff = True
        user.save(update_fields=['is_staff', 'password'])
        self.stdout.write(self.style.SUCCESS(f'Owner role enabled for {email}'))
