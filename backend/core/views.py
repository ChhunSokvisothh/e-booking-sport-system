"""Backward-compatible exports for the feature-based API modules."""

from features.auth.api.views import auth_login
from features.auth.api.views import auth_logout
from features.auth.api.views import auth_me
from features.auth.api.views import auth_signup
from features.facility.api.views import FacilityViewSet
from features.facility.api.views import TimeSlotViewSet
from features.facility.api.views import live_slots_endpoint
from features.facility.api.views import slot_availability_endpoint
from features.booking.api.views import BookingViewSet
from features.booking.api.views import cancel_booking_endpoint
from features.booking.api.views import dashboard_summary_endpoint
from features.booking.api.views import mock_payment_endpoint
from features.chatbot.api.views import chat_endpoint
from features.owner.api.views import active_coupons_endpoint
from features.owner.api.views import owner_coupon_detail_endpoint
from features.owner.api.views import owner_coupons_endpoint
from features.owner.api.views import owner_facilities_endpoint
from features.owner.api.views import owner_facility_detail_endpoint
