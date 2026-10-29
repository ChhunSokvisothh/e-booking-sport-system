from rest_framework.permissions import BasePermission


class IsVenueOwner(BasePermission):
    message = 'Venue owner access required.'

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and (user.is_staff or user.is_superuser)
        )
