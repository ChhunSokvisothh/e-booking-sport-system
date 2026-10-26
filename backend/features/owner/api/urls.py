from django.urls import path

from features.owner.api.views import (
    active_coupons_endpoint,
    owner_coupon_detail_endpoint,
    owner_coupons_endpoint,
    owner_facilities_endpoint,
    owner_facility_detail_endpoint,
)

urlpatterns = [
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
