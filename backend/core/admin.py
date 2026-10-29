from django.contrib import admin
from django.utils import timezone

from .models import Booking, ChatMessage, ChatSession, Facility, OwnerApplication, TimeSlot

admin.site.register(Facility)
admin.site.register(TimeSlot)
admin.site.register(Booking)
admin.site.register(ChatSession)
admin.site.register(ChatMessage)

@admin.action(description='Approve selected owner applications')
def approve_owner_applications(modeladmin, request, queryset):
    for application in queryset:
        application.status = OwnerApplication.Status.APPROVED
        application.reviewed_at = timezone.now()
        application.save(update_fields=['status', 'reviewed_at'])
        application.user.is_staff = True
        application.user.save(update_fields=['is_staff'])


@admin.register(OwnerApplication)
class OwnerApplicationAdmin(admin.ModelAdmin):
    list_display = ('venue_name', 'user', 'status', 'created_at', 'reviewed_at')
    list_filter = ('status',)
    actions = [approve_owner_applications]
