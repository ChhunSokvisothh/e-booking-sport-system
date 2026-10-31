from django.urls import path

from features.auth.api.views import auth_login, auth_logout, auth_me, auth_signup, owner_signup
from features.auth.api.admin_owner_applications import admin_owner_applications, review_owner_application

urlpatterns = [
    path('api/auth/signup/', auth_signup, name='auth-signup'),
    path('api/auth/owner-signup/', owner_signup, name='owner-signup'),
    path('api/admin/owner-applications/', admin_owner_applications, name='admin-owner-applications'),
    path('api/admin/owner-applications/<int:application_id>/review/', review_owner_application, name='admin-review-owner-application'),
    path('api/auth/login/', auth_login, name='auth-login'),
    path('api/auth/logout/', auth_logout, name='auth-logout'),
    path('api/auth/me/', auth_me, name='auth-me'),
]
