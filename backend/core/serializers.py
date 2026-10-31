from rest_framework import serializers

from .models import Booking, Coupon, Facility, TimeSlot


class FacilitySerializer(serializers.ModelSerializer):
    class Meta:
        model = Facility
        fields = [
            'id',
            'name',
            'sport_type',
            'is_indoor',
            'description',
            'location_name',
            'latitude',
            'longitude',
            'base_price_per_hour',
            'rating',
            'image_url',
            'gallery_image_urls',
            'amenities',
            'opening_hours',
            'contact_phone',
            'website_url',
            'surface_type',
            'cancellation_policy',
            'court_count',
            'owner_user_id',
            'is_active',
            'archived_at',
        ]


class TimeSlotSerializer(serializers.ModelSerializer):
    facility = FacilitySerializer(read_only=True)
    occupancy_rate = serializers.FloatField(read_only=True)
    has_space = serializers.BooleanField(read_only=True)

    class Meta:
        model = TimeSlot
        fields = [
            'id',
            'facility',
            'start_at',
            'end_at',
            'max_bookings',
            'current_bookings',
            'is_open',
            'reservation_hold_until',
            'slot_version',
            'occupancy_rate',
            'has_space',
        ]


class BookingSerializer(serializers.ModelSerializer):
    facility = FacilitySerializer(read_only=True)
    time_slot = TimeSlotSerializer(read_only=True)

    class Meta:
        model = Booking
        fields = [
            'id',
            'user_id',
            'facility',
            'time_slot',
            'start_at',
            'end_at',
            'duration_hours',
            'status',
            'payment_status',
            'base_price',
            'weather_discount',
            'empty_slot_discount',
            'final_price',
            'weather_rain_mm',
            'coupon_code',
            'coupon_discount',
            'booking_source',
            'chatbot_session_id',
            'created_at',
        ]


class CouponSerializer(serializers.ModelSerializer):
    is_currently_valid = serializers.BooleanField(read_only=True)

    class Meta:
        model = Coupon
        fields = [
            'id',
            'code',
            'title',
            'description',
            'discount_percent',
            'starts_at',
            'ends_at',
            'is_active',
            'owner_user_id',
            'is_currently_valid',
            'created_at',
        ]
