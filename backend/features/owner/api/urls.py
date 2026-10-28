from django.urls import path

from features.owner.api.views import (
    active_coupons_endpoint,
    owner_coupon_detail_endpoint,
    owner_coupons_endpoint,
    owner_facilities_endpoint,
    owner_facility_detail_endpoint,
    owner_application_endpoint,
    owner_application_review_endpoint,
    owner_subscription_endpoint,
    owner_checkout_endpoint,
    owner_payment_confirm_endpoint,
    owner_analytics_endpoint,
)

urlpatterns = [
    path('api/owner/applications/', owner_application_endpoint, name='owner-application'),
    path('api/owner/applications/<int:application_id>/review/', owner_application_review_endpoint, name='owner-application-review'),
    path('api/owner/subscription/', owner_subscription_endpoint, name='owner-subscription'),
    path('api/owner/checkout/', owner_checkout_endpoint, name='owner-checkout'),
    path('api/owner/payment/confirm/', owner_payment_confirm_endpoint, name='owner-payment-confirm'),
    path('api/owner/analytics/', owner_analytics_endpoint, name='owner-analytics'),
    path('api/coupons/active/', active_coupons_endpoint, name='active-coupons-endpoint'),
    path('api/coupons/owner/', owner_coupons_endpoint, name='owner-coupons-endpoint'),
    path(
        'api/coupons/owner/<int:coupon_id>/',
        owner_coupon_detail_endpoint,
        name='owner-coupon-detail-endpoint',
    ),
    path('api/facilities/owner/', owner_facilities_endpoint, name='owner-facilities-endpoint'),
    path(
        'api/facilities/owner/<int:facility_id>/',
        owner_facility_detail_endpoint,
        name='owner-facility-detail-endpoint',
    ),
]
