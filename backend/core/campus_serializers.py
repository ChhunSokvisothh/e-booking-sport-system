from rest_framework import serializers
from .models import Campus, CampusPhoto, Facility


class CampusPhotoSerializer(serializers.ModelSerializer):
    class Meta:
        model = CampusPhoto
        fields = ['id', 'image_url', 'caption', 'sort_order']


class CampusSerializer(serializers.ModelSerializer):
    photos = CampusPhotoSerializer(many=True, read_only=True)
    facilities = serializers.SerializerMethodField()

    class Meta:
        model = Campus
        fields = [
            'id', 'name', 'description', 'address', 'latitude', 'longitude',
            'contact_phone', 'contact_email', 'cover_image_url', 'opening_hours',
            'amenities', 'cancellation_policy', 'photos', 'facilities',
        ]

    def get_facilities(self, obj):
        from .serializers import FacilitySerializer
        return FacilitySerializer(
            obj.facilities.filter(is_active=True, archived_at__isnull=True).order_by('sport_type', 'name'),
            many=True,
        ).data
