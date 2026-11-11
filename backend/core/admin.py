from django.contrib import admin

from .models import Booking, ChatMessage, ChatSession, Facility, OwnerApplication, TimeSlot, UserProfile

admin.site.register(Facility)
admin.site.register(TimeSlot)
admin.site.register(Booking)
admin.site.register(ChatSession)
admin.site.register(ChatMessage)

@admin.register(OwnerApplication)
class OwnerApplicationAdmin(admin.ModelAdmin):
    list_display = ('venue_name', 'user', 'status', 'created_at', 'reviewed_at')
    list_filter = ('status',)
    readonly_fields = ('status', 'reviewed_at', 'created_at')


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'display_name', 'preferred_city', 'favorite_sport', 'updated_at')
    search_fields = ('user__email', 'display_name', 'preferred_city')
