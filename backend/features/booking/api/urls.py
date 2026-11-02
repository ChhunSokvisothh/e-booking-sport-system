from django.urls import include, path
from rest_framework.routers import DefaultRouter

from features.booking.api.views import (
    BookingViewSet,
    cancel_booking_endpoint,
    dashboard_summary_endpoint,
    mock_payment_endpoint,
    manual_booking_endpoint,
    retry_telegram_invoice,
)

router = DefaultRouter()
router.register(r'bookings', BookingViewSet, basename='booking')

urlpatterns = [
    path('api/dashboard/summary/', dashboard_summary_endpoint, name='dashboard-summary'),
    path('api/mock-payment/', mock_payment_endpoint, name='mock-payment-endpoint'),
    path('api/bookings/<int:booking_id>/telegram-invoice/retry/', retry_telegram_invoice, name='telegram-invoice-retry'),
    path('api/bookings/manual/', manual_booking_endpoint, name='manual-booking'),
    path('api/bookings/<int:booking_id>/cancel/', cancel_booking_endpoint, name='booking-cancel'),
    path('api/', include(router.urls)),
]
