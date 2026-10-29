from django.urls import path

from features.auth.api.views import auth_login, auth_logout, auth_me, auth_signup, owner_signup

urlpatterns = [
    path('api/auth/signup/', auth_signup, name='auth-signup'),
    path('api/auth/owner-signup/', owner_signup, name='owner-signup'),
    path('api/auth/login/', auth_login, name='auth-login'),
    path('api/auth/logout/', auth_logout, name='auth-logout'),
    path('api/auth/me/', auth_me, name='auth-me'),
]
