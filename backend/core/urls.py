from django.urls import include, path

urlpatterns = [
    path('', include('features.auth.api.urls')),
    # Owner routes must precede the generic facilities/<pk>/ router route.
    path('', include('features.owner.api.urls')),
    path('', include('features.facility.api.urls')),
    path('', include('features.booking.api.urls')),
    path('', include('features.chatbot.api.urls')),
]
