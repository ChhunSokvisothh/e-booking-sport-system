from django.urls import include, path
from rest_framework.routers import DefaultRouter

from features.facility.api.campus_views import campus_detail_endpoint, campus_list_endpoint, owner_campus_endpoint
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
    path('api/campuses/', campus_list_endpoint, name='campus-list'),
    path('api/campuses/<int:campus_id>/', campus_detail_endpoint, name='campus-detail'),
    path('api/owner/campus/', owner_campus_endpoint, name='owner-campus-profile'),
    path('api/slots/live/', live_slots_endpoint, name='slots-live'),
    path('api/slot-availability/', slot_availability_endpoint, name='slot-availability'),
    path('api/live-slots/', live_slots_endpoint, name='live-slots'),
    path('api/', include(router.urls)),
]
