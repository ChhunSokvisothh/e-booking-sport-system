from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone


class SportType(models.TextChoices):
    FOOTBALL = 'football', 'Football'
    BILLIARD = 'billiard', 'Billiard'
    PICKLEBALL = 'pickleball', 'Pickleball'
    VOLLEYBALL = 'volleyball', 'Volleyball'
    BASKETBALL = 'basketball', 'Basketball'
    FUTSAL = 'futsal', 'Futsal'
    TENNIS = 'tennis', 'Tennis'
    BADMINTON = 'badminton', 'Badminton'


class BookingStatus(models.TextChoices):
    PENDING = 'pending', 'Pending'
    CONFIRMED = 'confirmed', 'Confirmed'
    CANCELLED = 'cancelled', 'Cancelled'
    RESCHEDULED = 'rescheduled', 'Rescheduled'


class PaymentStatus(models.TextChoices):
    MOCK_PENDING = 'mock_pending', 'Mock Pending'
    MOCK_PAID = 'mock_paid', 'Mock Paid'
    MOCK_FAILED = 'mock_failed', 'Mock Failed'


class BookingSource(models.TextChoices):
    MANUAL = 'manual', 'Manual App Booking'
    CHATBOT = 'chatbot', 'Chatbot Booking'


class TelegramIdentity(models.Model):
    telegram_user_id = models.BigIntegerField(unique=True)
    user = models.ForeignKey('auth.User', on_delete=models.CASCADE, related_name='telegram_identities')
    username = models.CharField(max_length=255, blank=True)
    first_name = models.CharField(max_length=255, blank=True)
    linked_at = models.DateTimeField(auto_now_add=True)


class TelegramLoginAttempt(models.Model):
    token_hash = models.CharField(max_length=64, unique=True)
    status = models.CharField(max_length=12, default='pending')
    used = models.BooleanField(default=False)
    user = models.ForeignKey('auth.User', null=True, blank=True, on_delete=models.CASCADE)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)


class Facility(models.Model):
    name = models.CharField(max_length=120)
    sport_type = models.CharField(max_length=32, choices=SportType.choices)
    is_indoor = models.BooleanField(default=False)
    description = models.TextField(blank=True)
    location_name = models.CharField(max_length=255)
    latitude = models.FloatField(default=11.5564)
    longitude = models.FloatField(default=104.9282)
    base_price_per_hour = models.DecimalField(max_digits=10, decimal_places=2)
    rating = models.DecimalField(max_digits=2, decimal_places=1, default=Decimal('4.5'))
    image_url = models.URLField(blank=True)
    owner_user_id = models.UUIDField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    archived_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['sport_type', 'name']
        indexes = [
            models.Index(fields=['sport_type', 'is_indoor', 'is_active']),
        ]

    def __str__(self):
        venue = 'Indoor' if self.is_indoor else 'Outdoor'
        return f'{self.name} ({self.sport_type} - {venue})'


class TimeSlot(models.Model):
    class AvailabilityState(models.TextChoices):
        AVAILABLE = 'available', 'Available'
        FULL = 'full', 'Full'
        CLOSED = 'closed', 'Closed'

    facility = models.ForeignKey(Facility, on_delete=models.CASCADE, related_name='time_slots')
    start_at = models.DateTimeField()
    end_at = models.DateTimeField()

    max_bookings = models.PositiveIntegerField(default=1)
    current_bookings = models.PositiveIntegerField(default=0)
    is_open = models.BooleanField(default=True)
    availability_state = models.CharField(
        max_length=12,
        choices=AvailabilityState.choices,
        default=AvailabilityState.AVAILABLE,
        db_index=True,
    )
    availability_updated_at = models.DateTimeField(auto_now=True)
    reservation_hold_until = models.DateTimeField(null=True, blank=True)
    slot_version = models.PositiveIntegerField(default=1)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['start_at']
        constraints = [
            models.CheckConstraint(check=models.Q(end_at__gt=models.F('start_at')), name='slot_end_after_start'),
            models.UniqueConstraint(fields=['facility', 'start_at', 'end_at'], name='unique_slot_per_facility_time'),
        ]
        indexes = [
            models.Index(fields=['facility', 'start_at']),
            models.Index(fields=['start_at', 'end_at']),
            models.Index(fields=['is_open', 'availability_state', 'start_at']),
        ]

    def _compute_availability_state(self):
        if not self.is_open:
            return self.AvailabilityState.CLOSED
        if self.current_bookings >= self.max_bookings:
            return self.AvailabilityState.FULL
        return self.AvailabilityState.AVAILABLE

    def clean(self):
        if self.start_at < timezone.now() - timezone.timedelta(minutes=1):
            raise ValidationError('Cannot create slot in the past.')
        if self.current_bookings > self.max_bookings:
            raise ValidationError('current_bookings cannot exceed max_bookings.')

    def save(self, *args, **kwargs):
        if self.pk:
            previous_version = TimeSlot.objects.filter(pk=self.pk).values_list('slot_version', flat=True).first() or 1
            self.slot_version = previous_version + 1
        self.availability_state = self._compute_availability_state()

        update_fields = kwargs.get('update_fields')
        if update_fields is not None:
            computed_fields = {'availability_state', 'slot_version', 'availability_updated_at'}
            kwargs['update_fields'] = set(update_fields).union(computed_fields)

        super().save(*args, **kwargs)

    @property
    def occupancy_rate(self):
        if self.max_bookings == 0:
            return 1.0
        return self.current_bookings / self.max_bookings

    @property
    def has_space(self):
        return self.is_open and self.current_bookings < self.max_bookings

    def __str__(self):
        return f'{self.facility.name} | {self.start_at} - {self.end_at}'


class Booking(models.Model):
    user_id = models.UUIDField()

    facility = models.ForeignKey(Facility, on_delete=models.PROTECT, related_name='bookings')
    time_slot = models.ForeignKey(TimeSlot, on_delete=models.PROTECT, related_name='bookings')

    start_at = models.DateTimeField()
    end_at = models.DateTimeField()
    duration_hours = models.DecimalField(max_digits=4, decimal_places=2)

    status = models.CharField(max_length=20, choices=BookingStatus.choices, default=BookingStatus.PENDING)
    payment_status = models.CharField(max_length=20, choices=PaymentStatus.choices, default=PaymentStatus.MOCK_PENDING)

    base_price = models.DecimalField(max_digits=10, decimal_places=2)
    weather_discount = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal('0.00'))
    empty_slot_discount = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal('0.00'))
    final_price = models.DecimalField(max_digits=10, decimal_places=2)

    weather_rain_mm = models.FloatField(default=0.0)
    notes = models.TextField(blank=True)
    coupon_code = models.CharField(max_length=40, blank=True)
    coupon_discount = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal('0.00'))
    booking_source = models.CharField(max_length=20, choices=BookingSource.choices, default=BookingSource.MANUAL)
    chatbot_session_id = models.CharField(max_length=64, blank=True)
    refund_amount = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal('0.00'))
    refunded_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user_id', 'created_at']),
            models.Index(fields=['status', 'payment_status']),
            models.Index(fields=['booking_source', 'chatbot_session_id']),
            models.Index(fields=['coupon_code']),
        ]

    def clean(self):
        if self.end_at <= self.start_at:
            raise ValidationError('Booking end_at must be after start_at.')
        if self.duration_hours <= 0:
            raise ValidationError('duration_hours must be greater than zero.')

    @staticmethod
    def compute_dynamic_price(base_price_per_hour, duration_hours, is_indoor, rain_mm, occupancy_rate):
        base = (base_price_per_hour * duration_hours).quantize(Decimal('0.01'))

        weather_discount = Decimal('0.00')
        if (not is_indoor) and (rain_mm > 5.0):
            weather_discount = (base * Decimal('0.10')).quantize(Decimal('0.01'))

        empty_slot_discount = Decimal('0.00')
        if occupancy_rate < 0.30:
            empty_slot_discount = (base * Decimal('0.15')).quantize(Decimal('0.01'))

        final = (base - weather_discount - empty_slot_discount).quantize(Decimal('0.01'))
        if final < Decimal('0.00'):
            final = Decimal('0.00')

        return {
            'base_price': base,
            'weather_discount': weather_discount,
            'empty_slot_discount': empty_slot_discount,
            'final_price': final,
        }


class ChatSession(models.Model):
    user_id = models.UUIDField()
    session_id = models.CharField(max_length=64, unique=True)
    title = models.CharField(max_length=160, blank=True)
    last_message_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-last_message_at']
        indexes = [models.Index(fields=['user_id', '-last_message_at'])]
        db_table = 'core_chat_session'


class ChatMessage(models.Model):
    class Role(models.TextChoices):
        USER = 'user', 'User'
        ASSISTANT = 'assistant', 'Assistant'

    session = models.ForeignKey(
        ChatSession,
        on_delete=models.CASCADE,
        related_name='messages',
        to_field='session_id',
        db_column='session_id',
    )
    role = models.CharField(max_length=12, choices=Role.choices)
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at', 'id']
        indexes = [models.Index(fields=['session', 'created_at'])]
        db_table = 'core_chat_message'


class OwnerApplication(models.Model):
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        APPROVED = 'approved', 'Approved'
        REJECTED = 'rejected', 'Rejected'

    user = models.OneToOneField(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='owner_application',
    )
    venue_name = models.CharField(max_length=160)
    contact_phone = models.CharField(max_length=40, blank=True)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        db_table = 'core_owner_application'


class Coupon(models.Model):
    code = models.CharField(max_length=40, unique=True)
    title = models.CharField(max_length=120, blank=True)
    description = models.CharField(max_length=255, blank=True)
    discount_percent = models.DecimalField(max_digits=5, decimal_places=2)
    starts_at = models.DateTimeField()
    ends_at = models.DateTimeField()
    is_active = models.BooleanField(default=True)
    archived_at = models.DateTimeField(null=True, blank=True)
    owner_user_id = models.UUIDField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['code']),
            models.Index(fields=['is_active', 'starts_at', 'ends_at']),
        ]

    def clean(self):
        if self.ends_at <= self.starts_at:
            raise ValidationError('ends_at must be after starts_at.')
        if self.discount_percent <= Decimal('0'):
            raise ValidationError('discount_percent must be greater than zero.')
        if self.discount_percent > Decimal('100'):
            raise ValidationError('discount_percent cannot exceed 100.')

    def save(self, *args, **kwargs):
        self.code = (self.code or '').strip().upper()
        super().save(*args, **kwargs)

    @property
    def is_currently_valid(self):
        now = timezone.now()
        return self.is_active and self.starts_at <= now <= self.ends_at

    def __str__(self):
        return f'{self.code} ({self.discount_percent}% )'
