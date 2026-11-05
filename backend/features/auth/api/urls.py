from django.urls import path

from features.auth.api.views import (\n    auth_login, auth_logout, auth_me, auth_signup, owner_signup, auth_profile,\n    avatar_upload_url, avatar_upload_complete, avatar_delete,\n)

urlpatterns = [
    path('api/auth/signup/', auth_signup, name='auth-signup'),
    path('api/auth/owner-signup/', owner_signup, name='owner-signup'),
    path('api/auth/login/', auth_login, name='auth-login'),
    path('api/auth/logout/', auth_logout, name='auth-logout'),
    path('api/auth/me/', auth_me, name='auth-me'),
    path('api/auth/profile/', auth_profile, name='auth-profile'),\n    path('api/auth/profile/avatar/upload-url/', avatar_upload_url, name='avatar-upload-url'),\n    path('api/auth/profile/avatar/complete/', avatar_upload_complete, name='avatar-upload-complete'),\n    path('api/auth/profile/avatar/', avatar_delete, name='avatar-delete'),
]
