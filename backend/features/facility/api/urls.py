from django.urls import include, path
from rest_framework.routers import DefaultRouter

from features.facility.api.favorites import favorite_facilities_endpoint, remove_favorite_facility_endpoint

from features.facility.api.views import (
    FacilityViewSet,
    TimeSlotViewSet,
    live_slots_endpoint,
    slot_availability_endpoint,
)

router = DefaultRouter()
router.register(r'facilities', FacilityViewSet, basename='facility')
router.register(r'slots', TimeSlotViewSet, basename='slot')

urlpatterns = [
    path('api/favorites/', favorite_facilities_endpoint, name='favorite-facilities'),
    path('api/favorites/<int:facility_id>/', remove_favorite_facility_endpoint, name='remove-favorite-facility'),
    path('api/slots/live/', live_slots_endpoint, name='slots-live'),
    path('api/slot-availability/', slot_availability_endpoint, name='slot-availability'),
    path('api/live-slots/', live_slots_endpoint, name='live-slots'),
    path('api/', include(router.urls)),
]
