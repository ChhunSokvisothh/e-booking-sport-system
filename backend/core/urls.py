from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    BookingViewSet,
    FacilityViewSet,
    TimeSlotViewSet,
    admin_set_role_endpoint,
    auth_login,
    auth_logout,
    auth_me,
    auth_signup,
    active_coupons_endpoint,
    cancel_booking_endpoint,
    chat_endpoint,
    dashboard_summary_endpoint,
    live_slots_endpoint,
    mock_payment_endpoint,
    owner_coupon_detail_endpoint,
    owner_coupons_endpoint,
    owner_facilities_endpoint,
    owner_facility_detail_endpoint,
    slot_availability_endpoint,
)

router = DefaultRouter()
router.register(r'facilities', FacilityViewSet, basename='facility')
router.register(r'slots', TimeSlotViewSet, basename='slot')
router.register(r'bookings', BookingViewSet, basename='booking')

urlpatterns = [
    path('api/auth/signup/', auth_signup, name='auth-signup'),
    path('api/auth/login/', auth_login, name='auth-login'),
    path('api/auth/logout/', auth_logout, name='auth-logout'),
    path('api/auth/me/', auth_me, name='auth-me'),
    path('api/dashboard/summary/', dashboard_summary_endpoint, name='dashboard-summary'),
    path('api/slots/live/', live_slots_endpoint, name='slots-live'),
    path('api/slot-availability/', slot_availability_endpoint, name='slot-availability'),
    path('api/live-slots/', live_slots_endpoint, name='live-slots'),
    path('api/chat/', chat_endpoint, name='chat-endpoint'),
    path('api/mock-payment/', mock_payment_endpoint, name='mock-payment-endpoint'),
    path('api/coupons/active/', active_coupons_endpoint, name='active-coupons-endpoint'),
    path('api/coupons/owner/', owner_coupons_endpoint, name='owner-coupons-endpoint'),
    path('api/coupons/owner/<int:coupon_id>/', owner_coupon_detail_endpoint, name='owner-coupon-detail-endpoint'),
    path('api/facilities/owner/', owner_facilities_endpoint, name='owner-facilities-endpoint'),
    path('api/facilities/owner/<int:facility_id>/', owner_facility_detail_endpoint, name='owner-facility-detail-endpoint'),
    path('api/bookings/<int:booking_id>/cancel/', cancel_booking_endpoint, name='booking-cancel'),
    path('api/', include(router.urls)),
    path('api/admin/set-role/', admin_set_role_endpoint, name='admin-set-role'),
]
