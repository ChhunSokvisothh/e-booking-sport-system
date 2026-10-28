from django.contrib import admin

from .models import Booking, Campus, CampusPhoto, Facility, OwnerApplication, OwnerSubscription, TimeSlot

admin.site.register(Facility)
admin.site.register(Campus)
admin.site.register(CampusPhoto)
admin.site.register(TimeSlot)
admin.site.register(Booking)


@admin.register(OwnerApplication)
class OwnerApplicationAdmin(admin.ModelAdmin):
    list_display = ('id', 'campus_name', 'user_id', 'status', 'created_at', 'reviewed_at')
    list_filter = ('status', 'sport_type', 'is_indoor')
    search_fields = ('campus_name', 'location_name', 'contact_phone')
    readonly_fields = ('created_at', 'updated_at')


@admin.register(OwnerSubscription)
class OwnerSubscriptionAdmin(admin.ModelAdmin):
    list_display = ('id', 'application', 'user_id', 'amount', 'currency', 'status', 'expires_at')
    list_filter = ('status', 'plan', 'currency')
    search_fields = ('payment_reference', 'application__campus_name')
