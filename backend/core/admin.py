from django.contrib import admin
from django.utils import timezone

from .models import Booking, ChatMessage, ChatSession, Facility, OwnerApplication, TimeSlot, UserProfile

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
        if not application.user.is_superuser and application.user.is_staff:
            application.user.is_staff = False
            application.user.save(update_fields=['is_staff'])


@admin.register(OwnerApplication)
class OwnerApplicationAdmin(admin.ModelAdmin):
    list_display = ('venue_name', 'user', 'status', 'created_at', 'reviewed_at')
    list_filter = ('status',)
    actions = [approve_owner_applications]


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'display_name', 'preferred_city', 'favorite_sport', 'updated_at')
    search_fields = ('user__email', 'display_name', 'preferred_city')
