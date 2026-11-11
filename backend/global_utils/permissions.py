from rest_framework.permissions import BasePermission

from global_utils.common import _is_owner_user


class IsVenueOwner(BasePermission):
    message = 'Venue owner access required.'

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and _is_owner_user(user)
        )
