from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from core.models import OwnerApplication


class Command(BaseCommand):
    help = 'Create or update a paid-status owner account for owner console login.'

    def add_arguments(self, parser):
        parser.add_argument('--email', required=True, help='Owner email')
        parser.add_argument('--password', required=True, help='Owner password (min 8 chars)')
        parser.add_argument('--venue-name', default='', help='Venue name (defaults to the email prefix)')

    def handle(self, *args, **options):
        email = (options['email'] or '').strip().lower()
        password = (options['password'] or '').strip()
        venue_name = (options.get('venue_name') or '').strip() or email.split('@')[0]

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

        if user.is_staff and not user.is_superuser:
            user.is_staff = False
            user.save(update_fields=['is_staff', 'password'])
        else:
            user.save(update_fields=['password'])

        OwnerApplication.objects.update_or_create(
            user=user,
            defaults={
                'venue_name': venue_name,
                'status': OwnerApplication.Status.APPROVED,
                'reviewed_at': timezone.now(),
            },
        )
        self.stdout.write(self.style.SUCCESS(f'Owner role enabled for {email}'))
