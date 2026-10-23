from django.urls import include, path
from rest_framework.routers import DefaultRouter

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
    path('api/slots/live/', live_slots_endpoint, name='slots-live'),
    path('api/slot-availability/', slot_availability_endpoint, name='slot-availability'),
    path('api/live-slots/', live_slots_endpoint, name='live-slots'),
    path('api/', include(router.urls)),
]
