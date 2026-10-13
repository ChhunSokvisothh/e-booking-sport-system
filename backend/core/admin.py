from django.contrib import admin

from .models import Booking, Facility, TimeSlot

admin.site.register(Facility)
admin.site.register(TimeSlot)
admin.site.register(Booking)
